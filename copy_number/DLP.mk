include weigelt-lab/Makefile.inc
include weigelt-lab/config/gatk.inc

LOGDIR ?= log/DLP.$(NOW)

bwamem : $(foreach sample,$(SAMPLES),bam/$(sample).bam) \
		 $(foreach sample,$(SAMPLES),qdnaseq/log2/100kb/$(sample).txt) \
		 summary/idx_metrics.txt \
		 summary/aln_metrics.txt \
		 summary/insert_metrics.txt \
		 summary/oxog_metrics.txt \
		 summary/gc_metrics.txt \
		 summary/wgs_metrics.txt \
		 summary/duplicate_metrics.txt		 

BWAMEM_THREADS = 8
BWAMEM_MEM_PER_THREAD = 2G

SAMTOOLS_THREADS = 4
SAMTOOLS_MEM_THREAD = 2G

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
	$$(call RUN,-c -n $(BWAMEM_THREADS) -s 1G -m $(BWAMEM_MEM_PER_THREAD) -p $(PROJECT_DIR)/bwamem -N $1/bwa_align,"set -o pipefail && \
																											        $$(BWA) mem -p -M \
																													-R \"@RG\tID:$1\tLB:$1\tPL:illumina\tSM:$1\" \
																													-t $$(BWAMEM_THREADS) $$(REF_FASTA) $$(<) | \
																													$$(SAMTOOLS) view -bhS - > $$(@)")

bwamem/$1/$1_cl_aln_srt.bam : bwamem/$1/$1_cl_aln.bam
	$$(call RUN,-c -n $(SAMTOOLS_THREADS) -s 1G -m $(SAMTOOLS_MEM_THREAD) -p $(PROJECT_DIR)/bwamem -N $1/sort_index,"set -o pipefail && \
																													 $$(SAMTOOLS) sort -@ $$(SAMTOOLS_THREADS) $$(<) -o $$(@) && \
																													 $$(SAMTOOLS) index $$(@) && \
																													 cp bwamem/$1/$1_cl_aln_srt.bam.bai bwamem/$1/$1_cl_aln_srt.bai")

bwamem/$1/$1_cl_aln_srt_FX.bam : bwamem/$1/$1_cl_aln_srt.bam
	$$(call RUN,-c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/bwamem -N $1/fix_mate,"set -o pipefail && \
																			 $$(FIX_MATE) \
																			 INPUT=$$(<) \
																			 OUTPUT=$$(@) \
																			 SORT_ORDER=coordinate \
																			 COMPRESSION_LEVEL=9 \
																			 CREATE_INDEX=true")
										      
bwamem/$1/$1_cl_aln_srt_FX_MD.bam : bwamem/$1/$1_cl_aln_srt_FX.bam
	$$(call RUN, -c -n 8 -s 1G -m 2G -v $(SAMBAMBA_ENV) -p $(PROJECT_DIR)/bwamem -N $1/mark_dup -w 12:00:00,"set -o pipefail && \
																											 $$(SAMBAMBA) \
																											 markdup \
																											 -t 8 \
																											 -l 9 \
																											 --tmpdir $$(TMPDIR) \
																											 $$(<) \
																											 $$(@)")

bam/$1.bam : bwamem/$1/$1_cl_aln_srt_FX_MD.bam
	$$(call RUN, -c -n 1 -s 0.5G -m 1G -p $(PROJECT_DIR)/bam -N $1/final_copy,"set -o pipefail && \
																			   cp $$(<) $$(@) && \
																			   cp $$(<).bai $$(@).bai && \
																			   cp $$(<).bai bam/$1.bai")

endef
$(foreach sample,$(SAMPLES),\
	$(eval $(call fastq-2-bam,$(sample))))
	
define qdnaseq-extract
qdnaseq/log2/100kb/$1.txt : bam/$1.bam
	$$(call RUN,-c -n 1 -s 8G -m 16G -p $(PROJECT_DIR)/qdnaseq -N $1 -v $(QDNASEQ_ENV),"set -o pipefail && \
																						$(RSCRIPT) $(SCRIPTS_DIR)/copy_number/qdna_seq.R \
																						--option 1 \
																						--sample_name $1 \
																						--bin_size 100 \
																						--output_file $$(@)")

qdnaseq/log2/500kb/$1.txt : bam/$1.bam
	$$(call RUN,-c -n 1 -s 8G -m 16G -p $(PROJECT_DIR)/qdnaseq -N $1 -v $(QDNASEQ_ENV),"set -o pipefail && \
																						$(RSCRIPT) $(SCRIPTS_DIR)/copy_number/qdna_seq.R \
																						--option 1 \
																						--sample_name $1 \
																						--bin_size 500 \
																						--output_file $$(@)")
	
endef
$(foreach sample,$(SAMPLES),\
		$(eval $(call qdnaseq-extract,$(sample))))
		

define picard-metrics
metrics/$1.idx_stats.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 2G -m 4G -p $(PROJECT_DIR)/metrics -N $1/idx_stats,"set -o pipefail && \
																			    $$(BAM_INDEX) \
																			    INPUT=$$(<) \
																			    > $$(@)")
									   
metrics/$1.aln_metrics.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 2G -m 4G -p $(PROJECT_DIR)/metrics -N $1/aln_metrics,"set -o pipefail && \
																			      $$(COLLECT_ALIGNMENT_METRICS) \
																			      REFERENCE_SEQUENCE=$$(REF_FASTA) \
																			      INPUT=$$(<) \
																			      OUTPUT=$$(@)")
									   
metrics/$1.insert_metrics.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 2G -m 4G -p $(PROJECT_DIR)/metrics -N $1/insert_metrics,"set -o pipefail && \
																					 $$(COLLECT_INSERT_METRICS) \
																					 INPUT=$$(<) \
																					 OUTPUT=$$(@) \
																					 HISTOGRAM_FILE=metrics/$1.insert_metrics.pdf \
																					 MINIMUM_PCT=0.05")
									   
metrics/$1.oxog_metrics.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 2G -m 4G -p $(PROJECT_DIR)/metrics -N $1/oxog_metrics,"set -o pipefail && \
																			       $$(COLLECT_OXOG_METRICS) \
																			       REFERENCE_SEQUENCE=$$(REF_FASTA) \
																			       INPUT=$$(<) \
																			       OUTPUT=$$(@)")
					    
metrics/$1.gc_metrics_summary.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 2G -m 4G -p $(PROJECT_DIR)/metrics -N $1/gc_metrics,"set -o pipefail && \
																			     $$(COLLECT_GC_BIAS) \
																			     INPUT=$$(<) \
																			     OUTPUT=metrics/$1.gc_metrics.txt \
																			     CHART_OUTPUT=metrics/$1.gc_metrics.pdf \
																			     REFERENCE_SEQUENCE=$$(REF_FASTA) \
																			     SUMMARY_OUTPUT=$$(@)")
																			     
metrics/$1.wgs_metrics.txt : bam/$1.bam
	$$(call RUN,-c -n 1 -s 2G -m 4G -p $(PROJECT_DIR)/metrics -N $1/wgs_metrics,"set -o pipefail && \
																				 $$(COLLECT_WGS_METRICS) \
																				 INPUT=$$(<) \
																				 OUTPUT=$$(@) \
																				 REFERENCE_SEQUENCE=$$(REF_FASTA)")

metrics/$1.duplicate_metrics.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 2G -m 4G -p $(PROJECT_DIR)/metrics -N $1/dup_metrics,"set -o pipefail && \
																			      $$(COLLECT_DUP_METRICS) \
																			      INPUT=$$(<) \
																			      METRICS_FILE=$$(@)")
							
endef
$(foreach sample,$(SAMPLES),\
	$(eval $(call picard-metrics,$(sample))))
	
summary/idx_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).idx_stats.txt)
	$(call RUN,-c -n 1 -s 24G -m 48G -p $(PROJECT_DIR)/summary -N summary/idx,"set -o pipefail && \
																			   $(RSCRIPT) $(SCRIPTS_DIR)/summary/wgs_metrics.R --option 1 --sample_names '$(SAMPLES)'")
                      
summary/aln_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).aln_metrics.txt)
	$(call RUN,-c -n 1 -s 24G -m 48G -p $(PROJECT_DIR)/summary -N summary/aln,"set -o pipefail && \
																			   $(RSCRIPT) $(SCRIPTS_DIR)/summary/wgs_metrics.R --option 2 --sample_names '$(SAMPLES)'")

summary/insert_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).insert_metrics.txt)
	$(call RUN,-c -n 1 -s 24G -m 48G -p $(PROJECT_DIR)/summary -N summary/insert,"set -o pipefail && \
																			      $(RSCRIPT) $(SCRIPTS_DIR)/summary/wgs_metrics.R --option 3 --sample_names '$(SAMPLES)'")
                      
summary/oxog_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).oxog_metrics.txt)
	$(call RUN,-c -n 1 -s 24G -m 48G -p $(PROJECT_DIR)/summary -N summary/oxog,"set -o pipefail && \
																			    $(RSCRIPT) $(SCRIPTS_DIR)/summary/wgs_metrics.R --option 4 --sample_names '$(SAMPLES)'")
                      
summary/gc_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).gc_metrics_summary.txt)
	$(call RUN,-c -n 1 -s 24G -m 48G -p $(PROJECT_DIR)/summary -N summary/gc,"set -o pipefail && \
																			  $(RSCRIPT) $(SCRIPTS_DIR)/summary/wgs_metrics.R --option 5 --sample_names '$(SAMPLES)'")
                      
summary/wgs_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).wgs_metrics.txt)
	$(call RUN,-c -n 1 -s 24G -m 48G -p $(PROJECT_DIR)/summary -N summary/wgs,"set -o pipefail && \
																			   $(RSCRIPT) $(SCRIPTS_DIR)/summary/wgs_metrics.R --option 6 --sample_names '$(SAMPLES)'")
                      
summary/duplicate_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).duplicate_metrics.txt)
	$(call RUN,-c -n 1 -s 24G -m 48G -p $(PROJECT_DIR)/summary -N summary/dup,"set -o pipefail && \
																			   $(RSCRIPT) $(SCRIPTS_DIR)/summary/wgs_metrics.R --option 7 --sample_names '$(SAMPLES)'")


..DUMMY := $(shell mkdir -p version; \
	     $(BWA) &> version/tmp.txt; \
	     head -3 version/tmp.txt | tail -2 > version/DLP.txt; \
	     rm version/tmp.txt; \
	     $(SAMTOOLS) --version >> version/DLP.txt; \
	     echo "gatk3" >> version/DLP.txt; \
	     $(GATK) --version >> version/DLP.txt; \
	     echo "picard" >> version/DLP.txt; \
	     $(PICARD) MarkIlluminaAdapters --version &>> version/DLP.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: bwamem clean

clean :
	rm -f bwamem/*/*_R1.fastq.gz && \
	rm -f bwamem/*/*_R2.fastq.gz && \
	rm -f bwamem/*/*_aln.bam && \
	rm -f bwamem/*/*_adapter-metrics.txt && \
	rm -f bwamem/*/*_cl.fastq.gz && \
	rm -f bwamem/*/*_cl_aln.bam && \
	rm -f bwamem/*/*_cl_aln_srt.bam* && \
	rm -f bwamem/*/*_cl_aln_srt.bai* && \
	rm -f bwamem/*/*_cl_aln_srt_FX.bam* && \
	rm -f bwamem/*/*_cl_aln_srt_FX.bai && \
	rm -f bwamem/*/*_cl_aln_srt_FX_MD.bam* && \
	rm -f metrics/*.idx_stats.txt && \
	rm -f metrics/*.aln_metrics.txt && \
	rm -f metrics/*.insert_metrics.txt && \
	rm -f metrics/*.insert_metrics.pdf && \
	rm -f metrics/*.oxog_metrics.txt && \
	rm -f metrics/*.gc_metrics_summary.txt && \
	rm -f metrics/*.gc_metrics.txt && \
	rm -f metrics/*.gc_metrics.pdf && \
	rm -f metrics/*.wgs_metrics.txt && \
	rm -f metrics/*.duplicate_metrics.txt
