cwlVersion: v1.0
class: Workflow
label: EMG assembly for paired end Illumina

requirements:
 - class: StepInputExpressionRequirement
 - class: SubworkflowFeatureRequirement
 - class: SchemaDefRequirement
   types: 
     - $import: ../tools/FragGeneScan-model.yaml
     - $import: ../tools/InterProScan-apps.yaml
     - $import: ../tools/InterProScan-protein_formats.yaml
     - $import: ../tools/esl-reformat-replace.yaml
     - $import: ../tools/biom-convert-table.yaml

inputs:
  sequencing_run_id: string
  forward_reads:
    type: File
    format: edam:format_1930  # FASTQ
  reverse_reads:
    type: File
    format: edam:format_1930  # FASTQ
  ncRNA_models: File[]
  ncRNA_model_clans: File
  fraggenescan_model: ../tools/FragGeneScan-model.yaml#model
  assembly_mem_limit:
    type: int
    doc: in Gb
  mapseq_ref:
    type: File
    format: edam:format_1929  # FASTA
    secondaryFiles: .mscluster
  mapseq_taxonomy: File

outputs:
  SSUs:
    type: File
    outputSource: extract_SSUs/sequences

  classifications:
    type: File
    outputSource: classify_SSUs/classifications

  scaffolds:
    type: File
    outputSource: discard_short_scaffolds/filtered_sequences

  pCDS:
    type: File
    outputSource: fraggenescan/predictedCDS

  annotations:
    type: File
    outputSource: interproscan/i5Annotations

  otu_visualization:
    type: File
    outputSource: visualize_otu_counts/otu_visualization 

  otu_counts_hdf5:
    type: File
    outputSource: convert_otu_counts_to_hdf5/result 
  
  otu_counts_json:
    type: File
    outputSource: convert_otu_counts_to_json/result 

steps:
  assembly:
    run: ../tools/metaspades.cwl
    in:
      forward_reads: forward_reads
      reverse_reads: reverse_reads
      memory_limit: assembly_mem_limit
    out: [ scaffolds ]

  discard_short_scaffolds:
    run: ../tools/discard_short_seqs.cwl
    in:
      sequences: assembly/scaffolds
      minimum_length: { default: 100 }
    out: [ filtered_sequences ]

  find_ncRNAs:
    run:  cmsearch-multimodel.cwl 
    in: 
      query_sequences: discard_short_scaffolds/filtered_sequences
      covariance_models: ncRNA_models
      clan_info: ncRNA_model_clans
    out: [ matches ]
  
  get_SSU_coords:
    run: ../tools/SSU-from-tablehits.cwl
    in:
      table_hits: find_ncRNAs/matches
    out: [ SSU_coordinates ]

  index_scaffolds:
    run: ../tools/esl-sfetch-index.cwl
    in:
      sequences: discard_short_scaffolds/filtered_sequences
    out: [ sequences_with_index ]

  extract_SSUs:
    run: ../tools/esl-sfetch-manyseqs.cwl
    in:
      indexed_sequences: index_scaffolds/sequences_with_index
      names: get_SSU_coords/SSU_coordinates
      names_contain_subseq_coords: { default: true }
    out: [ sequences ]

  classify_SSUs:
    run: ../tools/mapseq.cwl
    in:
      sequences: extract_SSUs/sequences
      database: mapseq_ref
      taxonomy: mapseq_taxonomy
    out: [ classifications ]

  convert_classifications_to_otu_counts:
    run: ../tools/mapseq2biom.cwl
    in:
       otu_table: mapseq_taxonomy
       label: sequencing_run_id
       query: classify_SSUs/classifications
    out: [ otu_counts, krona_otu_counts ]

  visualize_otu_counts:
    run: ../tools/krona.cwl
    in:
      otu_counts: convert_classifications_to_otu_counts/krona_otu_counts
    out: [ otu_visualization ]

  convert_otu_counts_to_hdf5:
    run: ../tools/biom-convert.cwl
    in:
       biom: convert_classifications_to_otu_counts/otu_counts
       hdf5: { default: true }
       table_type: { default: OTU Table }
    out: [ result ]

  convert_otu_counts_to_json:
    run: ../tools/biom-convert.cwl
    in:
       biom: convert_classifications_to_otu_counts/otu_counts
       json: { default: true }
       table_type: { default: OTU Table }
    out: [ result ]


  fraggenescan:
    run: ../tools/FragGeneScan1_20.cwl
    in:
      sequence: discard_short_scaffolds/filtered_sequences
      completeSeq: { default: true }
      model: fraggenescan_model
    out: [ predictedCDS ]

  remove_asterisks_and_reformat:
    run: ../tools/esl-reformat.cwl
    in:
      sequences: fraggenescan/predictedCDS
      replace: { default: { find: '*', replace: X } }
    out: [ reformatted_sequences ]

  interproscan:
    run: ../tools/InterProScan5.21-60.cwl
    in:
      proteinFile: remove_asterisks_and_reformat/reformatted_sequences
      applications:
        default:
          - Pfam
          - TIGRFAM
          - PRINTS
          - ProSitePatterns
          - Gene3D
      # outputFileType:
      #   valueFrom: TSV
    out: [i5Annotations]

$namespaces:
 edam: http://edamontology.org/
 s: http://schema.org/
$schemas:
 - http://edamontology.org/EDAM_1.16.owl
 - https://schema.org/docs/schema_org_rdfa.html

s:license: "https://www.apache.org/licenses/LICENSE-2.0"
s:copyrightHolder: "EMBL - European Bioinformatics Institute"