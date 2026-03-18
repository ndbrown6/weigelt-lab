ifndef CONFIG_INC

REF ?= b37
SEQ_PLATFORM ?= illumina

# conda
WEIGELT_LAB_ENV ?= $(HOME)/share/env/weigelt-lab-0.0.1
PIGZ_ENV ?= $(HOME)/share/env/pigz-2.8
GATK_ENV ?= $(HOME)/share/env/gatk-3.8-10
SAMBAMBA_ENV ?= $(HOME)/share/env/sambamba-0.8.2
FASTQ_SPLITTER_ENV ?= $(HOME)/share/env/fastqsplitter-1.2.0
CNVKIT_ENV ?= $(HOME)/share/env/cnvkit-0.9.9
MUTECT_ENV ?= $(HOME)/share/env/mutect-1.1.6
VARSCAN_ENV ?= $(HOME)/share/env/varscan-2.3.7
VCF2MAF_ENV ?= $(HOME)/share/env/vcf2maf-1.6.17
UPSINDEL_ENV ?= $(HOME)/share/env/ups-indel-20170908
STRELKA_ENV ?= $(HOME)/share/env/strelka-2.9.10
SCALPEL_ENV ?= $(HOME)/share/env/scalpel-0.5.3
PLATYPUS_ENV = $(HOME)/share/env/platypus-variant-0.8.1
FACETS_SUITE_ENV ?= $(HOME)/share/env/r-facets-suite-2.0.8
COPYNUMBER_ENV ?= $(HOME)/share/env/r-copynumber-1.38.0
KALLISTO_ENV ?= $(HOME)/share/env/kallisto-0.46.2
MANTA_ENV ?= $(HOME)/share/env/manta-0.29.6
SVABA_ENV ?= $(HOME)/share/env/svaba-1.1.0
GRIDSS_ENV ?= $(HOME)/share/env/gridss-2.13.2
DELLY_ENV ?= $(HOME)/share/env/delly-1.7.2
JASMINE_ENV ?= $(HOME)/share/env/jasminesv-1.1.5
SURVIVOR_ENV ?= $(HOME)/share/env/survivor-1.0.7
ANNOTATESV_ENV ?= $(HOME)/share/env/annot_sv-3.1.3
ARRIBA_ENV ?= $(HOME)/share/env/arriba-2.0.0
GENOMIC_ALIGNMENTS_ENV ?= $(HOME)/share/env/r-genomicalignments-1.34.0
GGPLOT2_ENV ?= $(HOME)/share/env/r-tidyverse-2.0.0
STARFUSION_ENV ?= $(HOME)/share/env/star-fusion-1.6.0
FUSIONSUMMARY_ENV ?= $(HOME)/share/env/fusion-summary-0.0.1
IMMUNE_ENV ?= $(HOME)/share/env/r-immunedeconv-2.1.0
MIMSI_ENV ?= $(HOME)/share/env/mimsi-0.4.4
POLYSOLVER_ENV ?= $(HOME)/share/env/hla-polysolver-0.0.1

# aliases
PYTHON ?= python
PERL ?= perl
RSCRIPT ?= Rscript
R ?= R
BWA ?= bwa
SAMTOOLS ?= samtools
SAMBAMBA ?= sambamba
BEDTOOLS ?= bedtools
PICARD ?= picard
GATK ?= gatk
MUTECT ?= mutect
VARSCAN ?= varscan
VCF2MAF ?= vcf2maf.pl
MAF2VCF ?= maf2vcf.pl
MAF2MAF ?= maf2maf.pl
CONFIGURE_STRELKA ?= $(STRELKA_ENV)/opt/strelka-2.9.10.centos6_x86_64/bin/configureStrelkaSomaticWorkflow.py
CONFIGURE_MANTA ?= $(MANTA_ENV)/opt/manta-0.29.6.centos5_x86_64/bin/configManta.py
ANNOTATE_SV ?= $(ANNOTATESV_ENV)/opt/AnnotSV/bin/AnnotSV
ARRIBA ?= $(ARRIBA_ENV)/opt/arriba_v2.0.0/arriba

# picard command lines
PICARD_MEM = 8G
PICARD_OPTS = VALIDATION_STRINGENCY=LENIENT MAX_RECORDS_IN_RAM=4000000 TMP_DIR=$(TMPDIR)
BAM_INDEX = $(PICARD) -Xmx$(PICARD_MEM) BamIndexStats $(PICARD_OPTS)
COLLECT_ALIGNMENT_METRICS = $(PICARD) -Xmx$(PICARD_MEM) CollectAlignmentSummaryMetrics $(PICARD_OPTS)
COLLECT_DUP_METRICS = $(PICARD) -Xmx$(PICARD_MEM) CollectDuplicateMetrics $(PICARD_OPTS)
COLLECT_GC_BIAS = $(PICARD) -Xmx$(PICARD_MEM) CollectGcBiasMetrics $(PICARD_OPTS)
COLLECT_HS_METRICS = $(PICARD) -Xmx$(PICARD_MEM) CollectHsMetrics $(PICARD_OPTS)
COLLECT_INSERT_METRICS = $(PICARD) -Xmx$(PICARD_MEM) CollectInsertSizeMetrics $(PICARD_OPTS)
COLLECT_OXOG_METRICS = $(PICARD) -Xmx$(PICARD_MEM) CollectOxoGMetrics $(PICAD_OPTS)
COLLECT_WGS_METRICS = $(PICARD) -Xmx$(PICARD_MEM) CollectWgsMetrics $(PICARD_OPTS)
COLLECT_RNASEQ_METRICS = $(PICARD) -Xmx$(PICARD_MEM) CollectRnaSeqMetrics $(PICARD_OPTS)
FASTQ_TO_SAM = $(PICARD) -Xmx$(PICARD_MEM) FastqToSam $(PICARD_OPTS)
FIX_MATE = $(PICARD) -Xmx$(PICARD_MEM) FixMateInformation $(PICARD_OPTS)
MARK_ADAPTERS = $(PICARD) -Xmx$(PICARD_MEM) MarkIlluminaAdapters $(PICARD_OPTS)
SAM_TO_FASTQ = $(PICARD) -Xmx$(PICARD_MEM) SamToFastq $(PICARD_OPTS)

# paths
SCRIPTS_DIR = weigelt-lab/dodo-cloning-kit
TMPDIR = $(HOME)/share/usr/$(USER)/tmp

endif
CONFIG_INC = true
