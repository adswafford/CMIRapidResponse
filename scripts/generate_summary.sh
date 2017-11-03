#!/bin/bash

# Fail the workflow at the first error
set -e
# Fail if there is a vairable not defined
set -u

# DEFINE WHERE THE SUPPORT FILES DIRECTORY IS
SUPPORT_FILES_DIR="/Users/jose/qiime_software/CMIRapidResponse/cmirr/support_files/"

# Check that all inputs have been provided
if [ "$#" -ne 1 ]; then
    echo "USAGE: rr_workflow.sh RESULTS_DIR"
    echo "NOTE: Always use absolute paths"
    exit 1
fi

RESULTS_DIR=$1

if [ ! -d ${RESULTS_DIR} ]; then
    echo "Results directory doesn't exist"
    exit 1
fi

# Create a helper function to avoid code duplication
function transferQzv {
    QZV=$1
    DEST=$2

    mkdir ${DEST}

    if [ ! -f ${QZV} ]; then
        # The QZV file does not exist, put the not available.html
        cp ${SUPPORT_FILES_DIR}/not_available.html ${DEST}/index.html
    else
        mkdir ${DEST}/tmp
        cp ${QZV} ${DEST}/tmp
        pushd ${DEST}/tmp
        unzip *.qzv
        mv */data/* ../
        popd
        rm -r ${DEST}/tmp
    fi
}


# Create the report directory
mkdir ${RESULTS_DIR}/report

# Copy the contents of the support files directory to the report directory
cp -R ${SUPPORT_FILES_DIR}/* ${RESULTS_DIR}/report

# Create the report results directory structure
mkdir ${RESULTS_DIR}/report/results

# Transfer the BIOM summary
transferQzv ${RESULTS_DIR}/q2_biom_summary.qzv ${RESULTS_DIR}/report/results/biom_summary

# Transfer the rarefied results
for depth in 1000 5000 10000
do
    EVENDIR=${RESULTS_DIR}/report/results/even${depth}
    RAREDIR=${RESULTS_DIR}/even_${depth}
    mkdir ${EVENDIR}
    # Transfer taxa bar plot
    transferQzv ${RAREDIR}/taxabarplot.qzv ${EVENDIR}/taxabarplot
    # Transfer bdiv
    for metric in unweighted_unifrac weighted_unifrac
    do
        transferQzv ${RAREDIR}/${metric}_emperor.qzv ${EVENDIR}/${metric}
    done
    # Transfer adiv
    for metric in observed_otus pielou_e shannon
    do
        transferQzv ${RAREDIR}/adiv_${metric}.qzv ${EVENDIR}/adiv_${metric}
    done
    # Transfer ancom
    transferQzv ${RAREDIR}/ancom.qzv ${EVENDIR}/ancom
done
