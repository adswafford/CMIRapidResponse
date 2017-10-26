#!/bin/bash

# Fail the workflow at the first error
set -e
# Fail if there is a vairable not defined
set -u

# DEFINE ENVIRONMENTS
# Qiime 1.9.1 environment
Q1ENV="source activate qiime"
# Qiime 2 environment
Q2ENV="source activate qiime2-2017.9"
# SEPP environment
SEPPENV="source activate sepp"

# NOTIFICATION EMAIL
EMAIL="josenavasmolina@gmail.com"

# DEFINE REFERENCE PATHS
GG88OTUS="/databases/gg/13_8/rep_set/88_otus.fasta"
GG88OTUSDB="/databases/gg/13_8/sortmerna/88_otus"
GG97OTUS="/databases/gg/13_8/rep_set/97_otus.fasta"
GG97TAX="/databases/gg/13_8/taxonomy/97_otu_taxonomy.txt"
GG97OTUSDB="/databases/gg/13_8/sortmerna/97_otus"

# DEFINE METADATA CATEGORY TO DO COMPARISONS
MDCAT="host_subject_id"

# Check that all inputs have been provided
if [ "$#" -ne 4 ]; then
    echo "USAGE: rr_workflow.sh FORWARD_READS_FASTQ BARCODE_READS_FASTQ MAPPING_FILE OUTPUT_DIR"
    echo "NOTE: Always use absolute paths"
    exit 1
fi

FWDREADS=$1
BCDREADS=$2
MAPFP=$3
OUTDIR=$4

# Input check: the sequence files and the mapping file should exist,
# while the output directory should not. All filepaths should be absolute
if [ ! -f ${FWDREADS} ]; then
    echo "Forward reads file doesn't exist"
    exit 1
fi
if [ ! -f ${BCDREADS} ]; then
    echo "Barcode reads file doesn't exist"
    exit 1
fi
if [ ! -f ${MAPFP} ]; then
    echo "Mapping file doesn't exist"
    exit 1
fi
if [ -d ${OUTDIR} ]; then
    echo "Output directory already exists"
    exit 1
fi

# Create the output directory
mkdir ${OUTDIR}

# Run split libraries
SLOUTDIR=${OUTDIR}/sl_out
echo "${Q1ENV}; split_libraries_fastq.py -i ${FWDREADS} -b ${BCDREADS} -m ${MAPFP} -o ${SLOUTDIR} --rev_comp_barcode --rev_comp_mapping_barcodes"

# Run deblurring
DEBLUROUT=${OUTDIR}/deblur_out
echo "${Q2ENV}; deblur workflow --seqs-fp ${SLOUTDIR}/seqs.fna --output-dir ${DEBLUROUT} -t 150 -O 31 --pos-ref-db-fp ${GG88OTUSDB} --pos-ref-fp ${GG88OTUS}"

# Assign taxonomy
ATAXOUT=${OUTDIR}/atax_out
echo "${Q1ENV}; assign_taxonomy.py -i ${DEBLUROUT}/reference-hit.seqs.fa -o ${ATAXOUT} -m sortmerna --sortmerna_threads 31 -r ${GG97OTUS} -t ${GG97TAX} --sortmerna_db ${GG97OTUSDB} --sortmerna_threads 31"
BIOMFP=${OUTDIR}/reference_hit_w_tax.biom
echo "${Q1ENV}; biom add-metadata -i ${DEBLUROUT}/reference-hit.biom -o ${BIOMFP} --observation-metadata-fp ${ATAXOUT}/reference-hit.seqs_tax_assignments.txt --observation-header OTUID,taxonomy --sc-separated taxonomy"

# Generate a phylogenetic tree with SEPP
SEPPOUT=${OUTDIR}/sepp_out
echo "${SEPPENV}; mkdir ${SEPPOUT}; cd ${SEPPOUT}; run-sepp.sh ${DEBLUROUT}/reference-hit.seqs.fa reference-hit -x 31"
# Import the tree for QIIME 2
Q2TREE=${OUTDIR}/reference-hit-tree.qza
echo "${Q2ENV}; qiime tools import --input-path ${SEPPOUT}/reference-hit_placement.tog.relabelled.tre --output-path ${Q2TREE} --type \"Phylogeny[Rooted]\""

# Generate a BIOM table summary using Qiime 2
echo "${Q2ENV}; qiime tools import --input-path ${BIOMFP} --output-path ${OUTDIR}/q2_biom.qza --type \"FeatureTable[Frequency]\""
echo "${Q2ENV}; qiime feature-table summarize --i-table ${OUTDIR}/q2_biom.qza --o-visualization ${OUTDIR}/q2_biom_summary.qzv --m-sample-metadata-file ${MAPFP}"

# We are going to do the analysis in 3 different rarefaction levels: 1000, 5000 and 10000
for depth in 1000 5000 10000
do
    EVENOUT=${OUTDIR}/even_${depth}
    # Rarefy the BIOM table
    echo "${Q1ENV}; mkdir ${EVENOUT}; single_rarefaction.py -i ${BIOMFP} -o ${EVENOUT}/biom_table_even_${depth}.biom -d ${depth}"

    # Import the needed files to QIIME2
    Q2BIOM=${EVENOUT}/biom_even_${depth}.qza
    Q2TAX=${EVENOUT}/taxonomy.qza
    echo "${Q2ENV}; qiime tools import --input-path ${EVENOUT}/biom_table_even_${depth}.biom --output-path ${Q2BIOM} --type \"FeatureTable[Frequency] % Properties(['uniform-sampling'])\""
    echo "${Q2ENV}; cmirr export-taxonomy -i ${EVENOUT}/biom_table_even_${depth}.biom -o ${EVENOUT}/taxonomy.txt"
    echo "${Q2ENV}; qiime tools import --input-path ${EVENOUT}/taxonomy.txt --output-path ${Q2TAX} --type \"FeatureData[Taxonomy]\""

    # Run beta diversity - we run 2 metrics: Unweighted UniFrac and Weighted Unifrac
    for metric in "unweighted_unifrac" "weighted_unifrac"
    do
        Q2DM=${EVENOUT}/bdiv_${metric}_dm.qza
        echo "${Q2ENV}; qiime diversity beta-phylogenetic-alt -p-metric ${metric} --i-table ${Q2BIOM} --i-phylogeny ${Q2TREE} --o-distance-matrix ${Q2DM} --p-n-jobs 31"

        # Generate a emperor plot
        Q2PC=${EVENOUT}/bdiv_${metric}_pc.qza
        echo "${Q2ENV}; qiime diversity pcoa --i-distance-matrix ${Q2DM} --o-pcoa ${Q2PC}"
        echo "${Q2ENV}; qiime emperor plot --i-pcoa ${Q2PC} --o-visualization ${EVENOUT}/${metric}_emperor.qzv --m-metadata-file ${MAPFP}"

        # Run beta correlation
        echo "qiime diversity beta-correlation --i-distance-matrix ${Q2DM} --m-metadata-file ${MAPFP} --m-metadata-category ${MDCAT} --p-method spearman --p-permutations 999 --o-visualization ${EVENOUT}/bdiv_${metric}_corr.qzv"

        # Run beta group significance
        echo "qiime diversity beta-group-significance --i-distance-matrix ${Q2DM} --m-metadata-file ${MDCAT} --m-metadata-category ${MDCAT} --p-method permanova --p-permutations 999 --o-visualization ${EVENOUT}/bdiv_${metric}_sig.qzv --p-pairwise"
    done

    # Run alpha diversity and alpha correlation
    echo "${Q2ENV}; qiime diversity alpha-phylogenetic --i-phylogeny ${Q2TREE} --i-table ${Q2BIOM} --p-metric faith_pd --o-alpha-diversity ${EVENOUT}/adiv_faith.qza"
    echo "qiime diversity alpha-correlation --i-alpha-diversity ${EVENOUT}/adiv_faith.qza --m-metadata-file ${MAPFP} --p-method spearman --o-visualization ${EVENOUT}/adiv_faith.qzv"

    for metric in "shannon" "observed_otus" "pielou_e"
    do
        echo "${Q2ENV}; qiime diversity alpha-phylogenetic --i-phylogeny ${Q2TREE} --i-table ${Q2BIOM} --p-metric faith_pd --o-alpha-diversity ${EVENOUT}/adiv_${metric}.qza"
        echo "qiime diversity alpha-correlation --i-alpha-diversity ${EVENOUT}/adiv_${metric}.qza --m-metadata-file ${MAPFP} --p-method spearman --o-visualization ${EVENOUT}/adiv_${metric}.qzv"
    done

    # Run taxa barplot
    echo "${Q2ENV}; qiime taxa barplot --i-table ${Q2BIOM} --i-taxonomy ${Q2TAX} --m-metadata-file ${MAPFP} --o-visualization ${EVENOUT}/taxabarplot.qzv"

    # Run differential abundance with ANCOM
    echo "${Q2ENV}; qiime composition add-pseudocount --i-table ${Q2BIOM} --o-composition-table ${EVENOUT}/composition_biom.qza"
    echo "${Q2ENV}; qiime composition ancom --i-table ${EVENOUT}/composition_biom.qza --m-metadata-file ${MAPFP} --m-metadata-category ${MDCAT} --o-visualization ${EVENOUT}ancom.qzv"
done
