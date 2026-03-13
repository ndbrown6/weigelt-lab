include weigelt-lab/Makefile.inc
include weigelt-lab/config/arriba.inc

LOGDIR ?= log/arriba_fusion.$(NOW)

smry : $(foreach sample,$(SAMPLES),arriba/$(sample)/fusions.tsv) \
       $(foreach sample,$(SAMPLES),arriba/$(sample)/fusions.pdf) \
       arriba/fusion_summary.txt
	 
STAR_THREADS ?= 16
STAR_MEM_THREAD ?= 4G
STAR_WALL_TIME ?= 72:00:00

SAMTOOLS_THREADS ?= 8
SAMTOOLS_MEM_THREAD ?= 2G
	 
PROJECT_DIR := $(notdir $(CURDIR))

define merge-fastq
arriba/$1/$1_R1.fastq.gz : $$(foreach split,$2,$$(word 1, $$(fq.$$(split))))
	$$(call RUN,-c -n 12 -s 0.5G -m 1G -w 12:00:00 -v $(PIGZ_ENV) -p $(PROJECT_DIR)/arriba -N $1/merge_R1,"set -o pipefail && \
																									       mkdir -p arriba/$1 && \
																									       pigz -cd $$(^) | pigz -c -p 12 > $$(@)")
    
arriba/$1/$1_R2.fastq.gz : $$(foreach split,$2,$$(word 2, $$(fq.$$(split))))
	$$(call RUN,-c -n 12 -s 0.5G -m 1G -w 12:00:00 -v $(PIGZ_ENV) -p $(PROJECT_DIR)/arriba -N $1/merge_R2,"set -o pipefail && \
																									       mkdir -p arriba/$1 && \
																									       pigz -cd $$(^) | pigz -c -p 12 > $$(@)")
endef
$(foreach sample,$(SAMPLES),\
	$(eval $(call merge-fastq,$(sample),$(split.$(sample)))))


define run-star-arriba
arriba/$1/$1.Aligned.out.bam : arriba/$1/$1_R1.fastq.gz arriba/$1/$1_R2.fastq.gz
	$$(call RUN,-c -n $(STAR_THREADS) -s 1G -m $(STAR_MEM_THREAD) -p $(PROJECT_DIR)/arriba -N $1/STAR -v $(ARRIBA_ENV) -w $(STAR_WALL_TIME),"set -o pipefail && \
																																			 STAR \
																																			 --runThreadN $$(STAR_THREADS) \
																																			 --genomeDir $$(STAR_INDEX_DIR) \
																																			 --genomeLoad NoSharedMemory \
																																			 --readFilesIn $$(<) $$(<<) \
																																			 --readFilesCommand zcat \
																																			 --outStd BAM_Unsorted \
																																			 --outSAMtype BAM Unsorted \
																																			 --outSAMunmapped Within \
																																			 --outBAMcompression 0 \
																																			 --outFilterMultimapNmax 50 \
																																			 --peOverlapNbasesMin 10 \
																																			 --alignSplicedMateMapLminOverLmate 0.5 \
																																			 --alignSJstitchMismatchNmax 5 -1 5 5 \
																																			 --chimSegmentMin 10 \
																																			 --chimOutType WithinBAM HardClip \
																																			 --chimJunctionOverhangMin 10 \
																																			 --chimScoreDropMax 30 \
																																			 --chimScoreJunctionNonGTAG 0 \
																																			 --chimScoreSeparation 1 \
																																			 --chimSegmentReadGapMax 3 \
																																			 --chimMultimapNmax 50 \
																																			 --outFileNamePrefix arriba/$1/$1. > arriba/$1/$1.Aligned.out.bam")

arriba/$1/$1.Aligned.sortedByCoord.out.bam : arriba/$1/$1.Aligned.out.bam
	$$(call RUN,-c -n $(SAMTOOLS_THREADS) -s 1G -m $(SAMTOOLS_MEM_THREAD) -p $(PROJECT_DIR)/arriba -N $1/sort,"set -o pipefail && \
																											   samtools sort \
																											   -@ $(SAMTOOLS_THREADS) \
																											   -m $(SAMTOOLS_MEM_THREAD) \
																											   -o $$(@) \
																											   $$(<) && \
																											   samtools index $$(@)")
																	 
arriba/$1/fusions.tsv : arriba/$1/$1.Aligned.out.bam
	$$(call RUN,-c -n 1 -s 24G -m 36G -p $(PROJECT_DIR)/arriba -N $1/arriba -v $(ARRIBA_ENV),"set -o pipefail && \
																							  $$(ARRIBA) -x arriba/$1/$1.Aligned.out.bam \
																							  -o arriba/$1/fusions.tsv \
																							  -O arriba/$1/discarded.tsv \
																							  -a $$(ASSEMBLY_FA) \
																							  -g $$(ANNOTATION_GTF) \
																							  -b $$(BLACKLIST_TSV) \
																							  -k $$(KNOWN_FUSIONS_TSV) \
																							  -t $$(KNOWN_FUSIONS_TSV) \
																							  -p $$(PROTEIN_DOMAINS_GFF3)")

arriba/$1/fusions.pdf : arriba/$1/fusions.tsv arriba/$1/$1.Aligned.sortedByCoord.out.bam
	$$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/arriba -N $1/draw_fusions -v $(GENOMIC_ALIGNMENTS_ENV),"set -o pipefail && \
																											    $$(RSCRIPT) $$(DRAW_FUSIONS) \
																											    --fusions=$$(<) \
																											    --annotation=$$(ANNOTATION_GTF) \
																											    --alignments=$$(<<) \
																											    --cytobands=$$(CYTOBAND) \
																											    --proteinDomains=$$(PROTEIN_DOMAINS_GFF3) \
																											    --output=$$(@)")

endef
$(foreach sample,$(SAMPLES),\
                $(eval $(call run-star-arriba,$(sample))))
				
arriba/fusion_summary.txt : $(foreach sample,$(SAMPLES),arriba/$(sample)/fusions.tsv)
	$(call RUN, -c -n 1 -s 16G -m 24G -p $(PROJECT_DIR)/arriba -N summary,"set -o pipefail && \
	    																   $(RSCRIPT) $(SCRIPTS_DIR)/summary/arriba_summary.R \
																		   --sample_names '$(SAMPLES)'")
									   
..DUMMY := $(shell mkdir -p version; \
	$(ARRIBA) -h > version/arriba_fusion.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean : 
	rm -f arriba/*/*_R1.fastq.gz && \
	rm -f arriba/*/*_R2.fastq.gz && \
	rm -f arriba/*/*.Aligned.out.bam* && \
	rm -f arriba/*/*.Aligned.sortedByCoord.out.bam* && \
	rm -f arriba/*/*.out && \
	rm -f arriba/*/*.tab