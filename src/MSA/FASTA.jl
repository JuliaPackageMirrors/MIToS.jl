immutable FASTA <: Format end

# FASTA Parser
# ============

function _pre_readfasta(io::AbstractString)
    seqs = split(io, '>')
    N = length(seqs) - 1

    IDS  = Array(ASCIIString, N)
    SEQS = Array(ASCIIString, N)

    for i in 1:N
        fields = split(seqs[i+1], '\n')
        IDS[i] = fields[1]
        SEQS[i] = replace(fields[2], r"\s+", "")
    end

    (IDS, SEQS)
end

function _pre_readfasta(io::IO)
    IDS  = ASCIIString[]
    SEQS = ASCIIString[]
    for (name, seq) in FastaReader{ASCIIString}(io) # FastaIO
        push!(IDS,  name)
        push!(SEQS, seq )
    end
    (IDS, SEQS)
end

function parse(io::Union{IO,AbstractString}, format::Type{FASTA}, output::Type{AnnotatedMultipleSequenceAlignment};
               generatemapping::Bool=false, useidcoordinates::Bool=false,
               deletefullgaps::Bool=true, checkalphabet::Bool=false, keepinserts::Bool=false)
    IDS, SEQS = _pre_readfasta(io)
    annot = Annotations()
    if keepinserts
        _keepinserts!(SEQS, annot)
    end
    if generatemapping
        MSA, MAP = useidcoordinates  && hascoordinates(IDS[1]) ? _to_msa_mapping(SEQS, IDS) : _to_msa_mapping(SEQS)
        setannotfile!(annot, "NCol", string(size(MSA,2)))
        setannotfile!(annot, "ColMap", join(vcat(1:size(MSA,2)), ','))
        for i in 1:length(IDS)
            setannotsequence!(annot, IDS[i], "SeqMap", MAP[i])
        end
    else
        MSA = convert(Matrix{Residue}, SEQS)
    end
    msa = AnnotatedMultipleSequenceAlignment(IndexedArray(IDS), MSA, annot)
    if checkalphabet
        deletenotalphabetsequences!(msa, SEQS)
    end
    if deletefullgaps
        deletefullgapcolumns!(msa)
    end
    msa
end

function parse(io::Union{IO,AbstractString}, format::Type{FASTA}, output::Type{MultipleSequenceAlignment};
               deletefullgaps::Bool=true, checkalphabet::Bool=false)
    IDS, SEQS = _pre_readfasta(io)
    msa = MultipleSequenceAlignment(IndexedArray(IDS), convert(Matrix{Residue}, SEQS))
    if checkalphabet
        deletenotalphabetsequences!(msa, SEQS)
    end
    if deletefullgaps
        deletefullgapcolumns!(msa)
    end
    msa
end

function parse(io::Union{IO,AbstractString}, format::Type{FASTA}, output::Type{Matrix{Residue}};
               deletefullgaps::Bool=true, checkalphabet::Bool=false)
    IDS, SEQS = _pre_readfasta(io)
    _strings_to_msa(SEQS, deletefullgaps, checkalphabet)
end

parse(io::Union{IO,AbstractString}, format::Type{FASTA}; generatemapping::Bool=false,
      useidcoordinates::Bool=false, deletefullgaps::Bool=true,
      checkalphabet::Bool=false, keepinserts::Bool=false) = parse(io, FASTA,
                                                                  AnnotatedMultipleSequenceAlignment;
                                                                  generatemapping=generatemapping,
                                                                  useidcoordinates=useidcoordinates,
                                                                  deletefullgaps=deletefullgaps,
                                                                  checkalphabet=checkalphabet,
                                                                  keepinserts=keepinserts)

# Print FASTA
# ===========

function print(io::IO, msa::AbstractMultipleSequenceAlignment, format::Type{FASTA})
    for i in 1:nsequences(msa)
        id = msa.id[i]
        seq = asciisequence(msa, i)
        println(io, string(">", id, "\n", seq))
    end
end

print(msa::MultipleSequenceAlignment, format::Type{FASTA}) = print(STDOUT, msa, FASTA)
