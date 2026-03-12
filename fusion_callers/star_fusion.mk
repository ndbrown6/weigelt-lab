include weigelt-lab/Makefile.inc

LOGDIR ?= log/star_fusion.$(NOW)

smry : $(foreach sample,$(SAMPLES),starfusion/$(sample)/taskcomplete) \
	   starfusion/fusion_summary.txt
	      
STAR_THREADS ?= 16
STAR_MEM_THREAD ?= 4G
STAR_WALL_TIME ?= 36:00:00

CTAT_LIB ?= $(HOME)/share/lib/ref_files/CTAT_GRCh37/GRCh37_gencode_v19_CTAT_lib_Apr032020/ctat_genome_lib_build_dir/

define merge-fastq
starfusion/$1/$1_R1.fastq : $$(foreach split,$2,$$(word 1, $$(fq.$$(split))))
	$$(call RUN,-c -n 1 -s 1G -m 2G -w 12:00:00 -v $(PIGZ_ENV) -p $(PROJECT_DIR)/starfusion -N $1/merge_R1,"set -o pipefail && \
																											mkdir -p starfusion/$1 && \
																											pigz -cd $$(^) > $$(@)")
    
starfusion/$1/$1_R2.fastq : $$(foreach split,$2,$$(word 2, $$(fq.$$(split))))
	$$(call RUN,-c -n 1 -s 1G -m 2G -w 12:00:00 -v $(PIGZ_ENV) -p $(PROJECT_DIR)/starfusion -N $1/merge_R2,"set -o pipefail && \
																											mkdir -p starfusion/$1 && \
																											pigz -cd $$(^) > $$(@)")
endef
$(foreach sample,$(SAMPLES),\
	$(eval $(call merge-fastq,$(sample),$(split.$(sample)))))


define star-fusion
starfusion/$1/taskcomplete : starfusion/$1/$1_R1.fastq starfusion/$1/$1_R2.fastq
	$$(call RUN,-n $(STAR_THREADS) -s 1G -m $(STAR_MEM_THREAD) -p $(PROJECT_DIR)/starfusion -N $1/STAR -v $(STARFUSION_ENV) -w $(STAR_WALL_TIME),"set -o pipefail && \
																																			      STAR-Fusion \
																																			      --left_fq $$(<) \
																																			      --right_fq $$(<<) \
																																			      --CPU $$(STAR_THREADS) \
																																			      --output_dir starfusion/$1 \
																																			      --genome_lib_dir $$(CTAT_LIB) && \
																																			      touch $$(@)")

endef
$(foreach sample,$(SAMPLES),\
	$(eval $(call star-fusion,$(sample))))
		
starfusion/summary.txt : $(foreach sample,$(SAMPLES),starfusion/$(sample)/taskcomplete)
	echo "FusionName\tJunctionReadCount\tSpanningFragCount\tSpliceType\tLeftGene\tLeftBreakpoint\tRightGene\tRightBreakpoint\tLargeAnchorSupport\tFFPM\tLeftBreakDinuc\tLeftBreakEntropy\tRightBreakDinuc\tRightBreakEntropy\tannots\tSampleName" > starfusion/summary.txt; \
	for i in $(SAMPLES); do \
		sed -e "1d" starfusion/$$i/star-fusion.fusion_predictions.abridged.tsv | sed "s/$$/\t$$i/" >> starfusion/summary.txt; \
	done
	

..DUMMY := $(shell mkdir -p version; \
	$(STARFUSION_ENV)/bin/$(STAR_FUSION) --help &> version/star_fusion.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean : 
	rm -f starfusion/*/*_R1.fastq && \
	rm -f starfusion/*/*_R2.fastq
