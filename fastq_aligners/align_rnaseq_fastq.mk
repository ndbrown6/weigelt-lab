include weigelt-lab/Makefile.inc

LOGDIR ?= log/align_rnaseq_fastq.$(NOW)

star : $(foreach sample,$(SAMPLES),star/$(sample)/$(sample)_R1.fastq.gz) \
       $(foreach sample,$(SAMPLES),star/$(sample)/$(sample)_R2.fastq.gz) \
       $(foreach sample,$(SAMPLES),star/$(sample)/$(sample).Aligned.sortedByCoord.out.bam) \
       $(foreach sample,$(SAMPLES),star/$(sample)/$(sample).Aligned.sortedByCoord.out.bam.bai) \
       $(foreach sample,$(SAMPLES),bam/$(sample).bam) \
       $(foreach sample,$(SAMPLES),bam/$(sample).bam.bai) \
       clean

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
	    --chimSegmentReadGapMax parameter 3 \
	    --alignSJstitchMismatchNmax 5 -1 5 5 \
	    --chimOutType WithinBAM \
	    --quantMode GeneCounts

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

..DUMMY := $(shell mkdir -p version; \
         echo "STAR" > version/align_rnaseq_fastq.txt; \
         STAR --version >> version/align_rnaseq_fastq.txt; \
         $(SAMTOOLS) --version >> version/align_rnaseq_fastq.txt)

.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean : $(foreach sample,$(SAMPLES),bam/$(sample).bam) \
	$(foreach sample,$(SAMPLES),bam/$(sample).bam.bai)
	$(call RUN,-c -n 1 -s 0.5G -m 1G -w 1:00:00 -p $(PROJECT_DIR) -N clean_up,"set -o pipefail && \
										   rm -f star/*/*_R1.fastq.gz && \
										   rm -f star/*/*_R2.fastq.gz")
