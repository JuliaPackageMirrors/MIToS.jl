# PDB ids from Pfam sequence annotations
# ======================================

const _regex_PDB_from_GS = r"PDB;\s+(\w+)\s+(\w);\s+\w+-\w+;" # i.e.: "PDB; 2VQC A; 4-73;\n"

"""Generates from a Pfam `msa` a `Dict{ASCIIString, Vector{Tuple{ASCIIString,ASCIIString}}}`.
Keys are sequence IDs and each value is a list of tuples containing PDB code and chain.

```
julia> getseq2pdb(msa)
Dict{ASCIIString,Array{Tuple{ASCIIString,ASCIIString},1}} with 1 entry:
  "F112_SSV1/3-112" => [("2VQC","A")]

```
"""
function getseq2pdb(msa::AnnotatedMultipleSequenceAlignment)
    dict = Dict{ASCIIString, Vector{Tuple{ASCIIString,ASCIIString}}}()
    for (k, v) in getannotsequence(msa)
        id, annot = k
        # i.e.: "#=GS F112_SSV1/3-112 DR PDB; 2VQC A; 4-73;\n"
        if annot == "DR" && ismatch(_regex_PDB_from_GS, v)
            for m in eachmatch(_regex_PDB_from_GS, v)
                if haskey(dict, id)
                    push!(dict[id], (m.captures[1], m.captures[2]))
                else
                    dict[id] = Tuple{ASCIIString,ASCIIString}[ (m.captures[1], m.captures[2]) ]
                end
            end
        end
    end
    sizehint!(dict, length(dict))
end

# Mapping PDB/Pfam
# ================

"""
This function returns a `Dict{Int64,ASCIIString}` with **MSA column numbers on the input file** as keys and PDB residue numbers as values.
The mapping is performed using SIFTS. This function needs correct *ColMap* and *SeqMap* annotations.
If you are working with a **downloaded Pfam MSA without modifications**, you should `read` it using `generatemapping=true` and `useidcoordinates=true`.
"""
function msacolumn2pdbresidue(seqid::ASCIIString,
    pdbid::ASCIIString,
    chain::ASCIIString,
    pfamid::ASCIIString,
    msa::AnnotatedMultipleSequenceAlignment,
    siftsfile::ASCIIString)
    siftsmap = siftsmapping(siftsfile, dbPfam, pfamid, dbPDB, lowercase(pdbid), chain=chain, missings=false)
    seqmap   = getsequencemapping(msa, seqid)
    colmap   = getcolumnmapping(msa)
    N = ncolumns(msa)
    m = Dict{Int,ASCIIString}()
    sizehint!(m, N)
    for i in 1:N
      m[colmap[i]] = get(siftsmap, seqmap[i], "")
    end
    m
end

"If you don't indicate the Pfam accession number (`pfamid`), this function tries to read the *AC* file annotation."
msacolumn2pdbresidue(seqid::ASCIIString, pdbid::ASCIIString, chain::ASCIIString,
           msa::AnnotatedMultipleSequenceAlignment, siftsfile::ASCIIString) = msacolumn2pdbresidue(seqid, pdbid, chain,
           ascii(split(getannotfile(msa, "AC"), '.')[1]), msa, siftsfile::ASCIIString)

"If you don't indicate the path to the `siftsfile` used in the mapping, this function downloads the SIFTS file in the current folder."
msacolumn2pdbresidue(seqid::ASCIIString, pdbid::ASCIIString, chain::ASCIIString,
           pfamid::ASCIIString, msa::AnnotatedMultipleSequenceAlignment) = msacolumn2pdbresidue(seqid, pdbid, chain,
           pfamid, msa, downloadsifts(pdbid))

msacolumn2pdbresidue(seqid::ASCIIString, pdbid::ASCIIString, chain::ASCIIString,
           msa::AnnotatedMultipleSequenceAlignment) = msacolumn2pdbresidue(seqid, pdbid, chain,
           ascii(split(getannotfile(msa, "AC"), '.')[1]), msa)

# PDB contacts for each column
# ============================

"""
This function takes an `AnnotatedMultipleSequenceAlignment` with correct *ColMap* annotations and two dicts:

1. The first is an `OrderedDict{ASCIIString,PDBResidue}` from PDB residue number to `PDBResidue`.

2. The second is a `Dict{Int,ASCIIString}` from **MSA column number on the input file** to PDB residue number.

This returns a `PairwiseListMatrix{Float64,false}` of `0.0` and `1.0` where `1.0` indicates a residue contact
(inter residue distance less or equal to 6.05 angstroms between any heavy atom). `NaN` indicates a missing value.
"""
function msacontacts(msa::AnnotatedMultipleSequenceAlignment, residues::OrderedDict{ASCIIString,PDBResidue}, column2residues::Dict{Int,ASCIIString}, distance_limit::Float64=6.05)
  colmap   = getcolumnmapping(msa)
  contacts = PairwiseListMatrices.PairwiseListMatrix(Float64, length(column2residues), colmap, false, NaN)
  @inbounds @iterateupper contacts false begin

    resnumi = get(:($column2residues), :($colmap)[i], "")
    resnumj = get(:($column2residues), :($colmap)[j], "")
    if resnumi != "" && resnumj != "" && haskey(:($residues), resnumi) && haskey(:($residues), resnumj)
      list[k] = Float64(:($contact)(:($residues)[resnumi], :($residues)[resnumj], :($distance_limit)))
    else
      list[k] = NaN
    end

  end
  contacts
end

# AUC (contact prediction)
# ========================

##############################
# MODIFICAR PARA USAR ColMap #
##############################

"""
This function takes a `msacontacts` or its list of contacts `contact_list` with 1.0 for true contacts and 0.0 for not contacts (NaN or other numbers for missing values).
Returns two `BitVector`s, the first with `true`s where `contact_list` is 1.0 and the second with `true`s where `contact_list` is 0.0. There are useful for AUC calculations.
"""
function get_contact_mask(contact_list::Vector{Float64})
  N = length(contact_list)
  true_contacts  = falses(N)
  false_contacts = trues(N) # In general, there are few contacts
  @inbounds for i in 1:N
    value = contact_list[i]
    if value == 1.0
      true_contacts[i] = true
    end
    if value != 0.0
      false_contacts[i] = false
    end
  end
  true_contacts, false_contacts
end

get_contact_mask(msacontacts::PairwiseListMatrix{Float64,false}) = get_contact_mask(getlist(msacontacts))

"""
Returns the Area Under a ROC (Receiver Operating Characteristic) Curve (AUC) of the `scores_list` for `true_contacts` prediction.
The three vectors should have the same length and `false_contacts` should be `true` where there are not contacts.
"""
AUC{T}(scores_list::Vector{T}, true_contacts::BitVector, false_contacts::BitVector) = 1 - auc(roc(scores_list[true_contacts], scores_list[false_contacts]))

"""
Returns the Area Under a ROC (Receiver Operating Characteristic) Curve (AUC) of the `scores` for `true_contacts` prediction.
`scores`, `true_contacts` and `false_contacts` should have the same number of elements and `false_contacts` should be `true` where there are not contacts.
"""
AUC{T}(scores::PairwiseListMatrix{T,false}, true_contacts::BitVector, false_contacts::BitVector) = AUC(getlist(scores), true_contacts, false_contacts)

"""
Returns the Area Under a ROC (Receiver Operating Characteristic) Curve (AUC) of the `scores` for `msacontact` prediction.
`msacontact` should have 1.0 for true contacts and 0.0 for not contacts (NaN or other numbers for missing values).
"""
function AUC{T}(scores::PairwiseListMatrix{T,false}, msacontacts::PairwiseListMatrix{Float64,false})
  scores_list  = getlist(scores)
  contact_list = getlist(msacontacts)
  length(scores_list) != length(contact_list) && throw(ErrorException("Lists need to have the same number of elements."))
  true_contacts, false_contacts = get_contact_mask(contact_list)
  AUC(scores_list, true_contacts, false_contacts)
end