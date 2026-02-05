include weigelt-lab/Makefile.inc

LOGDIR ?= log/align_rnaseq_fastq.$(NOW)

star : $(foreach sample,$(SAMPLES),bam/$(sample).bam) \
       $(foreach sample,$(SAMPLES),bam/$(sample).bam.bai) \
       $(foreach sample,$(SAMPLES),metrics/$(sample)_rnaseq_metrics.txt) \
       $(foreach sample,$(SAMPLES),metrics/$(sample)_alignment_metrics.txt) \
       $(foreach sample,$(SAMPLES),metrics/$(sample)_insert_metrics.txt) \
       summary/rnaseq_metrics.txt \
       summary/alignment_metrics.txt \
       summary/insert_metrics.txt \
       summary/insert_summary.txt

STAR_THREADS = 16
STAR_MEM_THREAD = 4G

SAMTOOLS_THREADS = 4
SAMTOOLS_MEM_THREAD = 2G

STAR_OPTS = --genomeDir $(STAR_REF) \
	    --outSAMtype BAM SortedByCoordinate \
	    --twopassMode Basic \
	    --outReadsUnmapped None \
	    --chimSegmentMin 12 \
	    --chimJunctionOverhangMin 12 \
	    --alignSJDBoverhangMin 10 \
	    --alignMatesGapMax 200000 \
	    --alignIntronMax 200000 \
	    --chimSegmentReadGapMax 3 \
	    --alignSJstitchMismatchNmax 5 -1 5 5 \
	    --chimOutType WithinBAM \
	    --quantMode GeneCounts
	    
REF_FLAT ?= $(HOME)/share/lib/resource_files/refFlat_ensembl.v75.txt
RIBOSOMAL_INTERVALS ?= $(HOME)/share/lib/resource_files/Homo_sapiens.GRCh37.75.rRNA.interval_list
STRAND_SPECIFICITY ?= NONE

PROJECT_DIR := $(notdir $(CURDIR))

define merge-fastq
star/$1/$1_R1.fastq.gz : $$(foreach split,$2,$$(word 1, $$(fq.$$(split))))
    $$(call RUN,-c -n 12 -s 0.5G -m 1G -w 2:00:00 -p $(PROJECT_DIR)/star -N $1/merge_R1,"set -o pipefail && \
    											 zcat $$(^) | gzip -c > $$(@)")
    
star/$1/$1_R2.fastq.gz : $$(foreach split,$2,$$(word 2, $$(fq.$$(split))))
    $$(call RUN,-c -n 12 -s 0.5G -m 1G -w 2:00:00 -p $(PROJECT_DIR)/star -N $1/merge_R2,"set -o pipefail && \
    											 zcat $$(^) | gzip -c > $$(@)")
endef
$(foreach sample,$(SAMPLES),\
        $(eval $(call merge-fastq,$(sample),$(split.$(sample)))))
	

define align-fastq
star/$1/$1.Aligned.sortedByCoord.out.bam : star/$1/$1_R1.fastq.gz star/$1/$1_R2.fastq.gz
    $$(call RUN,-c -n $(STAR_THREADS) -s 2G -m $(STAR_MEM_THREAD) -w 8:00:00 -p $(PROJECT_DIR)/star -N $1/star_align,"set -o pipefail && \
    														      STAR $$(STAR_OPTS) \
														      --outFileNamePrefix star/$1/$1. \
														      --runThreadN $$(STAR_THREADS) \
														      --outSAMattrRGline \"ID:$1\" \"LB:$1\" \"SM:$1\" \"PL:illumina\" \
														      --readFilesIn $$(^) \
														      --readFilesCommand zcat")
                                   
star/$1/$1.Aligned.sortedByCoord.out.bam.bai : star/$1/$1.Aligned.sortedByCoord.out.bam
    $$(call RUN,-c -n $(SAMTOOLS_THREADS) -s 1G -m $(SAMTOOLS_MEM_THREAD) -w 1:00:00 -p $(PROJECT_DIR)/star -N $1/index_bam,"set -o pipefail && \
    															     $$(SAMTOOLS) index -@ $$(SAMTOOLS_THREADS) $$(<)")

bam/$1.bam : star/$1/$1.Aligned.sortedByCoord.out.bam
    $$(call RUN,-c -n 1 -s 0.5G -m 1G -w 1:00:00 -p $(PROJECT_DIR)/bam -N $1/copy_bam,"set -o pipefail && \
    										       cp $$(<) $$(@)")
                                   
bam/$1.bam.bai : star/$1/$1.Aligned.sortedByCoord.out.bam.bai
    $$(call RUN,-c -n 1 -s 0.5G -m 1G -w 1:00:00 -p $(PROJECT_DIR)/bam -N $1/copy_bai,"set -o pipefail && \
    										       cp $$(<) $$(@)")
endef
$(foreach sample,$(SAMPLES),\
    $(eval $(call align-fastq,$(sample))))
    
define picard-metrics
metrics/$1_rnaseq_metrics.txt : bam/$1.bam
	$$(call RUN,-c -n 1 -s 6G -m 12G -p $(PROJECT_DIR)/metrics -N $1/rnaseq_metrics,"set -o pipefail && \
											 $$(COLLECT_RNASEQ_METRICS) \
											 INPUT=$$(<) \
											 OUTPUT=$$(@) \
											 REF_FLAT=$$(REF_FLAT) \
											 RIBOSOMAL_INTERVALS=$$(RIBOSOMAL_INTERVALS) \
											 CHART_OUTPUT=metrics/$1_rnaseq_metrics.pdf \
											 STRAND_SPECIFICITY=$$(STRAND_SPECIFICITY)")

metrics/$1_alignment_metrics.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 6G -m 12G -p $(PROJECT_DIR)/metrics -N $1/aln_metrics,"set -o pipefail && \
										       $$(COLLECT_ALIGNMENT_METRICS) \
										       REFERENCE_SEQUENCE=$$(REF_FASTA) \
										       INPUT=$$(<) \
										       OUTPUT=$$(@)")

metrics/$1_insert_metrics.txt : bam/$1.bam
	$$(call RUN,-c -n 1 -s 6G -m 12G -p $(PROJECT_DIR)/metrics -N $1/insert_metrics,"set -o pipefail && \
											 $$(COLLECT_INSERT_METRICS) \
											 INPUT=$$(<) \
											 OUTPUT=$$(@) \
											 HISTOGRAM_FILE=metrics/$1_insert_metrics.pdf")

endef
$(foreach sample,$(SAMPLES),\
		$(eval $(call picard-metrics,$(sample))))
		
summary/rnaseq_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample)_rnaseq_metrics.txt)
	$(call RUN, -c -n 1 -s 4G -m 6G -p $(PROJECT_DIR)/summary -N summary/rnaseq,"set -o pipefail && \
										     $(RSCRIPT) $(SCRIPTS_DIR)/summary/rnaseq_metrics.R --option 1 --sample_names '$(SAMPLES)'")

summary/alignment_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample)_alignment_metrics.txt)
	$(call RUN, -c -n 1 -s 4G -m 6G -p $(PROJECT_DIR)/summary -N summary/aln,"set -o pipefail && \
										  $(RSCRIPT) $(SCRIPTS_DIR)/summary/rnaseq_metrics.R --option 2 --sample_names '$(SAMPLES)'")
									 
summary/insert_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample)_insert_metrics.txt)
	$(call RUN, -c -n 1 -s 4G -m 6G -p $(PROJECT_DIR)/summary -N summary/insert,"set -o pipefail && \
										     $(RSCRIPT) $(SCRIPTS_DIR)/summary/rnaseq_metrics.R --option 3 --sample_names '$(SAMPLES)'")

summary/insert_summary.txt : $(foreach sample,$(SAMPLES),metrics/$(sample)_insert_metrics.txt)
	$(call RUN, -c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/summary -N summary/insert,"set -o pipefail && \
										       $(RSCRIPT) $(SCRIPTS_DIR)/summary/rnaseq_metrics.R --option 4 --sample_names '$(SAMPLES)'")


..DUMMY := $(shell mkdir -p version; \
         echo "STAR" > version/align_rnaseq_fastq.txt; \
         STAR --version >> version/align_rnaseq_fastq.txt; \
         $(SAMTOOLS) --version >> version/align_rnaseq_fastq.txt; \
	 echo "picard" >> version/align_rnaseq_fastq.txt; \
	 $(PICARD) CollectRnaSeqMetrics --version &>> version/align_rnaseq_fastq.txt; \
	 R --version >> version/align_rnaseq_fastq.txt)

.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean : 
	rm -f star/*/*_R1.fastq.gz && \
	rm -f star/*/*_R2.fastq.gz && \
	rm -f star/*/*.Aligned.sortedByCoord.out.bam*
