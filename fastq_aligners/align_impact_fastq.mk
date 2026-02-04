include weigelt-lab/Makefile.inc
include weigelt-lab/config/gatk.inc

LOGDIR ?= log/align_impact_fastq.$(NOW)

bwamem : $(foreach sample,$(SAMPLES),bam/$(sample).bam) \
	 $(foreach sample,$(SAMPLES),metrics/$(sample).idx_stats.txt) \
	 $(foreach sample,$(SAMPLES),metrics/$(sample).aln_metrics.txt) \
	 $(foreach sample,$(SAMPLES),metrics/$(sample).insert_metrics.txt) \
	 $(foreach sample,$(SAMPLES),metrics/$(sample).oxog_metrics.txt) \
	 $(foreach sample,$(SAMPLES),metrics/$(sample).gc_metrics_summary.txt) \
	 $(foreach sample,$(SAMPLES),metrics/$(sample).hs_metrics.txt) \
	 $(foreach sample,$(SAMPLES),metrics/$(sample).duplicate_metrics.txt) \
	 summary/idx_metrics.txt \
	 summary/aln_metrics.txt \
	 summary/insert_metrics.txt \
	 summary/oxog_metrics.txt \
	 summary/gc_metrics.txt \
	 summary/hs_metrics.txt \
	 summary/duplicate_metrics.txt
	 
BWAMEM_THREADS = 8
BWAMEM_MEM_PER_THREAD = 2G

SAMTOOLS_THREADS = 4
SAMTOOLS_MEM_THREAD = 2G

GATK_THREADS = 4
GATK_MEM_THREAD = 4G

TARGETS_LIST := $(TARGETS_FILE:.bed=.list)
BAITS_LIST := $(BAITS_FILE:.bed=.list)

PROJECT_DIR := $(notdir $(CURDIR))

define merge-fastq
bwamem/$1/$1_R1.fastq.gz : $$(foreach split,$2,$$(word 1, $$(fq.$$(split))))
	$$(call RUN,-c -n 1 -s 0.5G -m 1G -p $(PROJECT_DIR)/bwamem -N $1/merge_R1,"set -o pipefail && \
										   zcat $$(^) | gzip -c > $$(@)")
	
bwamem/$1/$1_R2.fastq.gz : $$(foreach split,$2,$$(word 2, $$(fq.$$(split))))
	$$(call RUN,-c -n 1 -s 0.5G -m 1G -p $(PROJECT_DIR)/bwamem -N $1/merge_R2,"set -o pipefail && \
										   zcat $$(^) | gzip -c > $$(@)")
endef
$(foreach sample,$(SAMPLES),\
		$(eval $(call merge-fastq,$(sample),$(split.$(sample)))))
		
define fastq-2-bam
bwamem/$1/$1_aln.bam : bwamem/$1/$1_R1.fastq.gz bwamem/$1/$1_R2.fastq.gz
	$$(call RUN,-c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/bwamem -N $1/fastq2sam,"set -o pipefail && \
										  $$(FASTQ_TO_SAM) \
										  FASTQ=bwamem/$1/$1_R1.fastq.gz \
										  FASTQ2=bwamem/$1/$1_R2.fastq.gz \
										  OUTPUT=$$(@) \
										  SM=$1 \
										  LB=$1 \
										  PU=NA \
										  PL=illumina")
									       
bwamem/$1/$1_cl.fastq.gz : bwamem/$1/$1_aln.bam
	$$(call RUN,-c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/bwamem -N $1/clip_adapters,"set -o pipefail && \
										      $$(MARK_ADAPTERS) \
										      INPUT=$$(<) \
										      OUTPUT=/dev/stdout \
										      METRICS=bwamem/$1/$1_adapter-metrics.txt | \
										      $$(SAM_TO_FASTQ) \
										      INPUT=/dev/stdin \
										      FASTQ=$$(@) \
										      INTERLEAVE=true \
										      CLIPPING_ATTRIBUTE=XT \
										      CLIPPING_ACTION=X \
										      CLIPPING_MIN_LENGTH=25")
									       
bwamem/$1/$1_cl_aln.bam : bwamem/$1/$1_cl.fastq.gz
	$$(call RUN,-c -n $(BWAMEM_THREADS) -s 2G -m $(BWAMEM_MEM_PER_THREAD) -p $(PROJECT_DIR)/bwamem -N $1/bwa_align,"set -o pipefail && \
														        $$(BWA) mem -p -M \
															-R \"@RG\tID:$1\tLB:$1\tPL:illumina\tSM:$1\" \
															-t $$(BWAMEM_THREADS) $$(REF_FASTA) $$(<) | \
															$$(SAMTOOLS) view -bhS - > $$(@)")

bwamem/$1/$1_cl_aln_srt.bam : bwamem/$1/$1_cl_aln.bam
	$$(call RUN,-c -n $(SAMTOOLS_THREADS) -s 2G -m $(SAMTOOLS_MEM_THREAD) -p $(PROJECT_DIR)/bwamem -N $1/sort_index,"set -o pipefail && \
															 $$(SAMTOOLS) sort -@ $$(SAMTOOLS_THREADS) $$(<) -o $$(@) && \
															 $$(SAMTOOLS) index $$(@) && \
															 cp bwamem/$1/$1_cl_aln_srt.bam.bai bwamem/$1/$1_cl_aln_srt.bai")

bwamem/$1/$1_cl_aln_srt.intervals : bwamem/$1/$1_cl_aln_srt.bam
	$$(call RUN,-c -n $(GATK_THREADS) -s 2G -m $(GATK_MEM_THREAD) -v $(GATK_ENV) -p $(PROJECT_DIR)/bwamem -N $1/realign_targets,"set -o pipefail && \
																     $$(call GATK_CMD,16G) \
																     -T RealignerTargetCreator \
																     -I $$(^) \
																     -nt $$(GATK_THREADS) \
																     -R $$(REF_FASTA) \
																     -o $$(@) \
																     -known $$(KNOWN_INDELS)")
										      
bwamem/$1/$1_cl_aln_srt_IR.bam : bwamem/$1/$1_cl_aln_srt.bam bwamem/$1/$1_cl_aln_srt.intervals
	$$(call RUN,-c -n 1 -s 8G -m 16G -v $(GATK_ENV) -p $(PROJECT_DIR)/bwamem -N $1/indel_realign,"set -o pipefail && \
												      $$(call GATK_CMD,16G) \
												      -T IndelRealigner \
												      -I $$(<) \
												      -R $$(REF_FASTA) \
												      -targetIntervals $$(<<) \
												      -o $$(@) \
												      -known $$(KNOWN_INDELS)")
										      
bwamem/$1/$1_cl_aln_srt_IR_FX.bam : bwamem/$1/$1_cl_aln_srt_IR.bam
	$$(call RUN,-c -n 1 -s 8G -m 16G -p $(PROJECT_DIR)/bwamem -N $1/fix_mate,"set -o pipefail && \
										  $$(FIX_MATE) \
										  INPUT=$$(<) \
										  OUTPUT=$$(@) \
										  SORT_ORDER=coordinate \
										  COMPRESSION_LEVEL=9 \
										  CREATE_INDEX=true")
										      
bwamem/$1/$1_cl_aln_srt_IR_FX.grp : bwamem/$1/$1_cl_aln_srt_IR_FX.bam
	$$(call RUN,-c -n $(GATK_THREADS) -s 2G -m $(GATK_MEM_THREAD) -v $(GATK_ENV) -p $(PROJECT_DIR)/bwamem -N $1/base_recal,"set -o pipefail && \
																$$(call GATK_CMD,16G) \
																-T BaseRecalibrator \
																-R $$(REF_FASTA) \
																-knownSites $$(DBSNP) \
																-I $$(<) \
																-o $$(@)")

bwamem/$1/$1_cl_aln_srt_IR_FX_BR.bam : bwamem/$1/$1_cl_aln_srt_IR_FX.bam bwamem/$1/$1_cl_aln_srt_IR_FX.grp
	$$(call RUN,-c -n 1 -s 8G -m 16G -v $(GATK_ENV) -p $(PROJECT_DIR)/bwamem -N $1/apply_bqsr,"set -o pipefail && \
												   $$(call GATK_CMD,16G) \
												   -T PrintReads \
												   -R $$(REF_FASTA) \
												   -I $$(<) \
												   -BQSR $$(<<) \
												   -o $$(@)")

bwamem/$1/$1_cl_aln_srt_IR_FX_BR_MD.bam : bwamem/$1/$1_cl_aln_srt_IR_FX_BR.bam
	$$(call RUN, -c -n 8 -s 2G -m 4G -v $(SAMBAMBA_ENV) -p $(PROJECT_DIR)/bwamem -N $1/mark_dup -w 12:00:00,"set -o pipefail && \
														 $$(SAMBAMBA) \
														 markdup \
														 -t 8 \
														 -l 9 \
														 --tmpdir $$(TMPDIR) \
														 $$(<) \
														 $$(@)")

bam/$1.bam : bwamem/$1/$1_cl_aln_srt_IR_FX_BR_MD.bam
	$$(call RUN, -c -n 1 -s 0.5G -m 1G -p $(PROJECT_DIR)/bam -N $1/final_copy,"set -o pipefail && \
										   cp $$(<) $$(@) && \
										   cp $$(<).bai $$(@).bai && \
										   cp $$(<).bai bam/$1.bai")

endef
$(foreach sample,$(SAMPLES),\
	$(eval $(call fastq-2-bam,$(sample))))
		

define picard-metrics
metrics/$1.idx_stats.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/metrics -N $1/idx_stats,"set -o pipefail && \
										    $$(BAM_INDEX) \
										    INPUT=$$(<) \
										    > $$(@)")
									   
metrics/$1.aln_metrics.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/metrics -N $1/aln_metrics,"set -o pipefail && \
										      $$(COLLECT_ALIGNMENT_METRICS) \
										      REFERENCE_SEQUENCE=$$(REF_FASTA) \
										      INPUT=$$(<) \
										      OUTPUT=$$(@)")
									   
metrics/$1.insert_metrics.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/metrics -N $1/insert_metrics,"set -o pipefail && \
											 $$(COLLECT_INSERT_METRICS) \
											 INPUT=$$(<) \
											 OUTPUT=$$(@) \
											 HISTOGRAM_FILE=metrics/$1.insert_metrics.pdf \
											 MINIMUM_PCT=0.05")
									   
metrics/$1.oxog_metrics.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/metrics -N $1/oxog_metrics,"set -o pipefail && \
										       $$(COLLECT_OXOG_METRICS) \
										       REFERENCE_SEQUENCE=$$(REF_FASTA) \
										       INPUT=$$(<) \
										       OUTPUT=$$(@)")
					    
metrics/$1.gc_metrics_summary.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/metrics -N $1/gc_metrics,"set -o pipefail && \
										     $$(COLLECT_GC_BIAS) \
										     INPUT=$$(<) \
										     OUTPUT=metrics/$1.gc_metrics.txt \
										     CHART_OUTPUT=metrics/$1.gc_metrics.pdf \
										     REFERENCE_SEQUENCE=$$(REF_FASTA) \
										     SUMMARY_OUTPUT=$$(@)")

metrics/$1.hs_metrics.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/metrics -N $1/hs_metrics,"set -o pipefail && \
										     $$(COLLECT_HS_METRICS) \
										     REFERENCE_SEQUENCE=$$(REF_FASTA) \
										     INPUT=$$(<) \
										     OUTPUT=$$(@) \
										     BAIT_INTERVALS=$$(BAITS_LIST) \
										     TARGET_INTERVALS=$$(TARGETS_LIST)")
							
metrics/$1.duplicate_metrics.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/metrics -N $1/dup_metrics,"set -o pipefail && \
										      $$(COLLECT_DUP_METRICS) \
										      INPUT=$$(<) \
										      METRICS_FILE=$$(@)")
							
endef
$(foreach sample,$(SAMPLES),\
	$(eval $(call picard-metrics,$(sample))))
	
summary/idx_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).idx_stats.txt)
	$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/summary -N summary/idx,"set -o pipefail && \
										  $(RSCRIPT) $(SCRIPTS_DIR)/summary/bam_metrics.R --option 1 --sample_names '$(SAMPLES)'")
					  
summary/aln_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).aln_metrics.txt)
	$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/summary -N summary/aln,"set -o pipefail && \
										  $(RSCRIPT) $(SCRIPTS_DIR)/summary/bam_metrics.R --option 2 --sample_names '$(SAMPLES)'")

summary/insert_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).insert_metrics.txt)
	$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/summary -N summary/insert,"set -o pipefail && \
										     $(RSCRIPT) $(SCRIPTS_DIR)/summary/bam_metrics.R --option 3 --sample_names '$(SAMPLES)'")
					  
summary/oxog_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).oxog_metrics.txt)
	$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/summary -N summary/oxog,"set -o pipefail && \
										   $(RSCRIPT) $(SCRIPTS_DIR)/summary/bam_metrics.R --option 4 --sample_names '$(SAMPLES)'")
					  
summary/gc_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).gc_metrics_summary.txt)
	$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/summary -N summary/gc,"set -o pipefail && \
										 $(RSCRIPT) $(SCRIPTS_DIR)/summary/bam_metrics.R --option 5 --sample_names '$(SAMPLES)'")
					  
summary/hs_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).hs_metrics.txt)
	$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/summary -N summary/hs,"set -o pipefail && \
										 $(RSCRIPT) $(SCRIPTS_DIR)/summary/bam_metrics.R --option 6 --sample_names '$(SAMPLES)'")
					  
summary/duplicate_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).duplicate_metrics.txt)
	$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/summary -N summary/dup,"set -o pipefail && \
										  $(RSCRIPT) $(SCRIPTS_DIR)/summary/bam_metrics.R --option 7 --sample_names '$(SAMPLES)'")

..DUMMY := $(shell mkdir -p version; \
	     $(BWA) &> version/tmp.txt; \
	     head -3 version/tmp.txt | tail -2 > version/align_impact_fastq.txt; \
	     rm version/tmp.txt; \
	     $(SAMTOOLS) --version >> version/align_impact_fastq.txt; \
	     echo "gatk3" >> version/align_impact_fastq.txt; \
	     $(GATK) --version >> version/align_impact_fastq.txt; \
	     echo "picard" >> version/align_impact_fastq.txt; \
	     $(PICARD) MarkIlluminaAdapters --version &>> version/align_impact_fastq.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
	rm -f bwamem/*/*_R1.fastq.gz && \
	rm -f bwamem/*/*_R2.fastq.gz && \
	rm -f bwamem/*/*_aln.bam && \
	rm -f bwamem/*/*_adapter-metrics.txt && \
	rm -f bwamem/*/*_cl.fastq.gz && \
	rm -f bwamem/*/*_cl_aln.bam && \
	rm -f bwamem/*/*_cl_aln_srt.bam* && \
	rm -f bwamem/*/*_cl_aln_srt.bai* && \
	rm -f bwamem/*/*_cl_aln_srt.intervals && \
	rm -f bwamem/*/*_cl_aln_srt_IR.bam* && \
	rm -f bwamem/*/*_cl_aln_srt_IR.bai* && \
	rm -f bwamem/*/*_cl_aln_srt_IR_FX.bam* && \
	rm -f bwamem/*/*_cl_aln_srt_IR_FX.bai && \
	rm -f bwamem/*/*_cl_aln_srt_IR_FX.grp && \
	rm -f bwamem/*/*_cl_aln_srt_IR_FX_BR.bam* && \
	rm -f bwamem/*/*_cl_aln_srt_IR_FX_BR.bai* && \
	rm -f bwamem/*/*_cl_aln_srt_IR_FX_BR_MD.bam*