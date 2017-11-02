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
MDCAT="rr_test_group"

############################################################################
## DO NOT MODIFY ANYTHING BELOW HERE UNLESS YOU ARE CHANGING THE WORKFLOW ##
############################################################################

PBSMAIL="-m abe -M ${EMAIL}"

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

#######################
## UPSTREAM ANALYSES ##
#######################

# Create the output directory
mkdir ${OUTDIR}

# Run split libraries
SLOUTDIR=${OUTDIR}/sl_out
SLJID=`echo "${Q1ENV}; split_libraries_fastq.py -i ${FWDREADS} -b ${BCDREADS} -m ${MAPFP} -o ${SLOUTDIR} --rev_comp_barcode --rev_comp_mapping_barcodes" | qsub -N RRSL -l walltime=6:00:00 ${PBSMAIL}`

# Run deblurring
DEBLUROUT=${OUTDIR}/deblur_out
DEBLURJID=`echo "${Q2ENV}; deblur workflow --seqs-fp ${SLOUTDIR}/seqs.fna --output-dir ${DEBLUROUT} -t 150 -O 31 --pos-ref-db-fp ${GG88OTUSDB} --pos-ref-fp ${GG88OTUS}" | qsub -N RRDEBLUR -l walltime=2:00:00 -l nodes=1:ppn=32 -W depend-afterok:${SLJID} ${PBSMAIL}`

# Assign taxonomy
ATAXOUT=${OUTDIR}/atax_out
ATAXJID=`echo "${Q1ENV}; assign_taxonomy.py -i ${DEBLUROUT}/reference-hit.seqs.fa -o ${ATAXOUT} -m sortmerna --sortmerna_threads 31 -r ${GG97OTUS} -t ${GG97TAX} --sortmerna_db ${GG97OTUSDB} --sortmerna_threads 31" | qsub -N RRATAX -l walltime=2:00:00 -l nodes=1:ppn=32 -W depend-afterok:${DEBLURJID} ${PBSMAIL}`
BIOMFP=${OUTDIR}/reference_hit_w_tax.biom
ADDMETAJID=`echo "${Q1ENV}; biom add-metadata -i ${DEBLUROUT}/reference-hit.biom -o ${BIOMFP} --observation-metadata-fp ${ATAXOUT}/reference-hit.seqs_tax_assignments.txt --observation-header OTUID,taxonomy --sc-separated taxonomy" | qsub -N RRADDMETA -l walltime=0:15:00 -W depend-afterok:${ATAXJID} ${PBSMAIL}`

# Generate a phylogenetic tree with SEPP
SEPPOUT=${OUTDIR}/sepp_out
SEPPJID=`echo "${SEPPENV}; mkdir ${SEPPOUT}; cd ${SEPPOUT}; run-sepp.sh ${DEBLUROUT}/reference-hit.seqs.fa reference-hit -x 31" | qsub -N RRSEPP -l walltime=2:00:00 -l nodes=1:ppn=32 -W depend-afterok:${DEBLURJID} ${PBSMAIL}`
# Import the tree for QIIME 2
Q2TREE=${OUTDIR}/reference-hit-tree.qza
TREEIMPJID=`echo "${Q2ENV}; qiime tools import --input-path ${SEPPOUT}/reference-hit_placement.tog.relabelled.tre --output-path ${Q2TREE} --type \"Phylogeny[Rooted]\"" | qsub -N RRTREEIMP -l walltime=0:10:00 -W depend-afterok:${SEPPJID} ${PBSMAIL}`

# Generate a BIOM table summary using Qiime 2
BIOMIMPJID=`echo "${Q2ENV}; qiime tools import --input-path ${BIOMFP} --output-path ${OUTDIR}/q2_biom.qza --type \"FeatureTable[Frequency]\"" | qsub -N RRBIOMIMP -l walltime=0:15:00 -W depend-afterok:${ADDMETAJID} ${PBSMAIL}`
BIOMSUMPJI=`echo "${Q2ENV}; qiime feature-table summarize --i-table ${OUTDIR}/q2_biom.qza --o-visualization ${OUTDIR}/q2_biom_summary.qzv --m-sample-metadata-file ${MAPFP}" | qsub -N RRBIOMSUM -l walltime=0:30:00 -W depend-afterok:${BIOMIMPJID} ${PBSMAIL}`

#########################
## DOWNSTREAM ANALYSES ##
#########################

# We are going to do the analysis in 3 different rarefaction levels: 1000, 5000 and 10000
for depth in 1000 5000 10000
do
    EVENOUT=${OUTDIR}/even_${depth}
    # Rarefy the BIOM table
    SRJID=`echo "${Q1ENV}; mkdir ${EVENOUT}; single_rarefaction.py -i ${BIOMFP} -o ${EVENOUT}/biom_table_even_${depth}.biom -d ${depth}" | qsub -N RRSR${depth} -l walltime=0:30:00 -W depend-afterok:${ADDMETAJID} ${PBSMAIL}`

    # Import the needed files to QIIME2
    Q2BIOM=${EVENOUT}/biom_even_${depth}.qza
    Q2TAX=${EVENOUT}/taxonomy.qza
    EBIOMIMPJID=`echo "${Q2ENV}; qiime tools import --input-path ${EVENOUT}/biom_table_even_${depth}.biom --output-path ${Q2BIOM} --type \"FeatureTable[Frequency] % Properties(['uniform-sampling'])\"" | qsub -N RRBIOMIMP${depth} -l walltime=0:15:00 -W depend-afterok:${SRJID} ${PBSMAIL}`
    ETAXEXPPJID=`echo "${Q2ENV}; cmirr export-taxonomy --input-biom ${EVENOUT}/biom_table_even_${depth}.biom --output-taxa ${EVENOUT}/taxonomy.txt" | qsub -N RRTAXEXP${depth} -l walltime=0:15:00 -W depend-afterok:${SRJID} ${PBSMAIL}`
    ETAXIMPPJID=`echo "${Q2ENV}; qiime tools import --input-path ${EVENOUT}/taxonomy.txt --output-path ${Q2TAX} --type \"FeatureData[Taxonomy]\"" | qsub -N RRTAXIMP${depth} -l walltime=0:15:00 -W depend-afterok:${ETAXEXPPJID} ${PBSMAIL}`

    # Run beta diversity - we run 2 metrics: Unweighted UniFrac and Weighted Unifrac
    for metric in "unweighted_unifrac" "weighted_unifrac"
    do
        Q2DM=${EVENOUT}/bdiv_${metric}_dm.qza
        BDIVJID=`echo "${Q2ENV}; qiime diversity beta-phylogenetic-alt -p-metric ${metric} --i-table ${Q2BIOM} --i-phylogeny ${Q2TREE} --o-distance-matrix ${Q2DM} --p-n-jobs 31" | qsub -N RRBD${depth}${metric} -l walltime=4:00:00 -l nodes=1:ppn=32 -W depend-afterok:${EBIOMIMPJID}:${TREEIMPJID}`

        # Generate a emperor plot
        Q2PC=${EVENOUT}/bdiv_${metric}_pc.qza
        PCOAJID=`echo "${Q2ENV}; qiime diversity pcoa --i-distance-matrix ${Q2DM} --o-pcoa ${Q2PC}" | qsub -N RRPCOA${depth}${metric} -l walltime=2:00:00 -W depend-afterok:${BDIVJID}`
        EMPERORJID=`echo "${Q2ENV}; qiime emperor plot --i-pcoa ${Q2PC} --o-visualization ${EVENOUT}/${metric}_emperor.qzv --m-metadata-file ${MAPFP}" | qsub -N RREMP${depth}${metric} -l walltime=0:30:00 -W depend-afterok:${PCOAJID}`

        # Run beta correlation
        BCORRJID=`echo "qiime diversity beta-correlation --i-distance-matrix ${Q2DM} --m-metadata-file ${MAPFP} --m-metadata-category ${MDCAT} --p-method spearman --p-permutations 999 --o-visualization ${EVENOUT}/bdiv_${metric}_corr.qzv" | qsub -N RRBCORR${depth}${metric} -l walltime=1:00:00 -W depend-afterok:${BDIVJID}`

        # Run beta group significance
        BGSJID=`echo "qiime diversity beta-group-significance --i-distance-matrix ${Q2DM} --m-metadata-file ${MDCAT} --m-metadata-category ${MDCAT} --p-method permanova --p-permutations 999 --o-visualization ${EVENOUT}/bdiv_${metric}_sig.qzv --p-pairwise" | qsub -N RRBGS${depth}${metric} -l walltime=1:00:00 -W depend-afterok:${BDIVJID}`
    done

    # Run alpha diversity and alpha correlation
    ADIVJID=`echo "${Q2ENV}; qiime diversity alpha-phylogenetic --i-phylogeny ${Q2TREE} --i-table ${Q2BIOM} --p-metric faith_pd --o-alpha-diversity ${EVENOUT}/adiv_faith.qza" | qsub -N RRADF${depth} -l walltime=2:00:00 -W depend-afterok:${EBIOMIMPJID}:${TREEIMPJID}`
    ACORRJID=`echo "qiime diversity alpha-correlation --i-alpha-diversity ${EVENOUT}/adiv_faith.qza --m-metadata-file ${MAPFP} --p-method spearman --o-visualization ${EVENOUT}/adiv_faith.qzv" | qsub -N RRACORRF${depth} -l walltime=1:00:00 -W depend-afterok:${ADIVJID}`

    for metric in "shannon" "observed_otus" "pielou_e"
    do
        ADIVJID=`echo "${Q2ENV}; qiime diversity alpha --i-table ${Q2BIOM} --p-metric ${metric} --o-alpha-diversity ${EVENOUT}/adiv_${metric}.qza" | qsub -N RRAD${depth}${metric} -l walltime=2:00:00 -W depend-afterok:${EBIOMIMPJID}`
        ACORRJID=`echo "qiime diversity alpha-correlation --i-alpha-diversity ${EVENOUT}/adiv_${metric}.qza --m-metadata-file ${MAPFP} --p-method spearman --o-visualization ${EVENOUT}/adiv_${metric}.qzv" | qsub -N RRACORR${depth}${metric} -l walltime=1:00:00 -W depend-afterok:${ADIVJID}`
    done

    # Run taxa barplot
    TBPJID=`echo "${Q2ENV}; qiime taxa barplot --i-table ${Q2BIOM} --i-taxonomy ${Q2TAX} --m-metadata-file ${MAPFP} --o-visualization ${EVENOUT}/taxabarplot.qzv" | qsub -N RRTBP${depth} -l walltime=1:00:00 -W depend-afterok:${EBIOMIMPJID}:${ETAXIMPPJID}`

    # Run differential abundance with ANCOM
    CAPJID=`echo "${Q2ENV}; qiime composition add-pseudocount --i-table ${Q2BIOM} --o-composition-table ${EVENOUT}/composition_biom.qza" | qsub -N RRCAP${depth} -l walltime=1:00:00 -W depend-afterok:${EBIOMIMPJID}`
    CANCJID=`echo "${Q2ENV}; qiime composition ancom --i-table ${EVENOUT}/composition_biom.qza --m-metadata-file ${MAPFP} --m-metadata-category ${MDCAT} --o-visualization ${EVENOUT}/ancom.qzv" | qsub -N RRANC${depth} -l walltime=1:00:00 -W depend-afterok:${CAPJID}`
done
