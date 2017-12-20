# CMIRapidResponse

The "rr_workflow.sh" bash script in this directory can be used to automatically process 16S V4 amplicon sequences generated using the Earth Microbiome Project (EMP) 16S processing protocols (http://press.igsb.anl.gov/earthmicrobiome/protocols-and-standards/16s/) to create:
1. A BIOM summary (qiime2-summarize)
2. Taxonomy summary barplots (qiime2-barplot)
3. Emperor plots (principal coordinates analysis) of unweighted and weighted UniFrac beta diversity metrics (qiime2-plot and qiime2-beta-phylogenetic)
4. Barplots of alpha diversity with tests performed for each categorical metadata category by Kruskal–Wallis one-way ANOVA
5. Scatter plots of alpha diversity (Observed OTUs, Pielou's evenness, and Shannon Diversity) with the calculated Spearman's correlation coefficient.
6. Differential abundance testing with ANCOM, based on the specified metadata category. 

Dependencies:
1. Qiime 1.9.1: http://qiime.org/install/install.html
2. Qiime2-2017.9: https://docs.qiime2.org/2017.9/install/
3. SEPP: https://github.com/smirarab/sepp/blob/master/tutorial/sepp-tutorial.md

Usage:
1. Download this repository
2. Open rr_workflow.sh and make changes to the following parameters:

Specify the names of your local conda environments corresponding to these dependencies:
Q1ENV="source activate [qiime]"- replace 'qiime' with the name of your Qiime 1.9.1 environment if necessary
Q2ENV="source activate qiime2-2017.9"- replace 'qiime2-2017.9' with the name of your Qiime2 2017.9+ environment if necessary
SEPPENV="source activate sepp"- replace 'sepp' with the name of your SEPP environment if necessary

Provide your email address to be notified if the job fails
EMAIL="[your email address]"

Replace the paths to the GreenGenes databases as follows:
GG88OTUS="/databases/gg/13_8/rep_set/88_otus.fasta"
GG88OTUSDB="/databases/gg/13_8/sortmerna/88_otus"
GG97OTUS="/databases/gg/13_8/rep_set/97_otus.fasta"
GG97TAX="/databases/gg/13_8/taxonomy/97_otu_taxonomy.txt"
GG97OTUSDB="/databases/gg/13_8/sortmerna/97_otus"

Definte the number of jobs to distribute the tasks
NUMJOBS=8

Define the name of the metadata category to be used for testing beta group significance and differential abundances. Alpha diversity metrics will be calculated for all categorical metadata categories and alpha correlation will be performed for all categorical metadata categories.
MDCAT="[metadata category of interest]"

3. Save the bash and run using the command:
"rr_workflow.sh FORWARD_READS_FASTQ BARCODE_READS_FASTQ MAPPING_FILE OUTPUT_DIR"


