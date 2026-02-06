include modules/Makefile.inc
include modules/genome_inc/b37.inc

LOGDIR ?= log/cnv_kit.$(NOW)

cnv_kit : cnv_kit/target_bed/on_target.bed \
	  cnv_kit/target_bed/off_target.bed \
	  $(foreach sample,$(TUMOR_SAMPLES),cnv_kit/cnn/tumor/$(sample).targetcoverage.cnn) \
	  $(foreach sample,$(TUMOR_SAMPLES),cnv_kit/cnn/tumor/$(sample).antitargetcoverage.cnn) \
	  $(foreach sample,$(NORMAL_SAMPLES),cnv_kit/cnn/normal/$(sample).targetcoverage.cnn) \
	  $(foreach sample,$(NORMAL_SAMPLES),cnv_kit/cnn/normal/$(sample).antitargetcoverage.cnn) \
	  cnv_kit/reference/reference.cnr \
	  $(foreach sample,$(TUMOR_SAMPLES),cnv_kit/cnr/$(sample).cnr)
#	  $(foreach sample,$(TUMOR_SAMPLES),cnv_kit/segments/$(sample).txt) \
#	  $(foreach sample,$(TUMOR_SAMPLES),cnv_kit/plots/log2/$(sample).pdf) \
#	  $(foreach sample,$(TUMOR_SAMPLES),cnv_kit/plots/segmented/$(sample).pdf) \
#	  $(foreach sample,$(TUMOR_SAMPLES),cnv_kit/totalcopy/$(sample).txt) \
#	  $(foreach sample,$(TUMOR_SAMPLES),cnv_kit/plots/totalcopy/$(sample).pdf) \
#	  cnv_kit/summary/total_copy.txt \
#	  cnv_kit/summary/log2_ratio.txt
	  

REF_FLAT ?= ~/share/lib/resource_files/refFlat_ensembl.v75.txt
EXCLUDE_BED ?= ~/share/lib/bed_files/access-excludes.b37.bed

PROJECT_DIR := $(notdir $(CURDIR))

cnv_kit/target_bed/on_target.bed : $(TARGETS_FILE)
	$(call RUN,-c -n 4 -s 6G -m 8G -v $(CNVKIT_ENV) -p $(PROJECT_DIR) -N on_target,"set -o pipefail && \
											cnvkit.py target $(<) \
											--annotate $(REF_FLAT) \
											--split -o $(@)")

cnv_kit/target_bed/off_target.bed : cnv_kit/target_bed/on_target.bed
	$(call RUN,-c -n 4 -s 6G -m 8G -v $(CNVKIT_ENV) -p $(PROJECT_DIR) -N off_target,"set -o pipefail && \
											 cnvkit.py antitarget $(<) \
											 -g $(EXCLUDE_BED) \
											 -o $(@)")

define cnvkit-tumor-cnn
cnv_kit/cnn/tumor/$1.targetcoverage.cnn : bam/$1.bam cnv_kit/target_bed/on_target.bed
	$$(call RUN,-c -n 4 -s 6G -m 8G -v $(CNVKIT_ENV) -p $(PROJECT_DIR)/cnn -N $1/on_target,"set -o pipefail && \
												cnvkit.py coverage -p 4 -q 0 $$(<) $$(<<) -o $$(@)")

cnv_kit/cnn/tumor/$1.antitargetcoverage.cnn : bam/$1.bam cnv_kit/target_bed/off_target.bed
	$$(call RUN,-c -n 4 -s 6G -m 8G -v $(CNVKIT_ENV) -p $(PROJECT_DIR)/cnn -N $1/off_target,"set -o pipefail && \
												 cnvkit.py coverage -p 4 -q 0 $$(<) $$(<<) -o $$(@)")
endef
 $(foreach sample,$(TUMOR_SAMPLES),\
		$(eval $(call cnvkit-tumor-cnn,$(sample))))
		
define cnvkit-normal-cnn
cnv_kit/cnn/normal/$1.targetcoverage.cnn : bam/$1.bam cnv_kit/target_bed/on_target.bed
	$$(call RUN,-c -n 4 -s 6G -m 8G -v $(CNVKIT_ENV) -p $(PROJECT_DIR)/cnn -N $1/on_target,"set -o pipefail && \
												cnvkit.py coverage -p 4 -q 0 $$(<) $$(<<) -o $$(@)")

cnv_kit/cnn/normal/$1.antitargetcoverage.cnn : bam/$1.bam bam/$1.bam cnv_kit/target_bed/off_target.bed
	$$(call RUN,-c -n 4 -s 6G -m 8G -v $(CNVKIT_ENV) -p $(PROJECT_DIR)/cnn -N $1/off_target,"set -o pipefail && \
												 cnvkit.py coverage -p 4 -q 0 $$(<) $$(<<) -o $$(@)")
endef
 $(foreach sample,$(NORMAL_SAMPLES),\
		$(eval $(call cnvkit-normal-cnn,$(sample))))

cnv_kit/reference/reference.cnr : $(foreach sample,$(NORMAL_SAMPLES),cnv_kit/cnn/normal/$(sample).targetcoverage.cnn) $(foreach sample,$(NORMAL_SAMPLES),cnv_kit/cnn/normal/$(sample).antitargetcoverage.cnn)
	$(call RUN,-n 1 -s 24G -m 32G -v $(CNVKIT_ENV) -p $(PROJECT_DIR) -N reference,"set -o pipefail && \
										       sleep 30 && \
										       cnvkit.py reference cnv_kit/cnn/normal/*.cnn -f $(REF_FASTA) --no-edge -o $(@)")

define cnvkit-tumor-cnr
cnv_kit/cnr/$1.cnr : cnv_kit/cnn/tumor/$1.targetcoverage.cnn cnv_kit/cnn/tumor/$1.antitargetcoverage.cnn cnv_kit/reference/reference.cnr
	$$(call RUN,-c -s 6G -m 8G -v $(CNVKIT_ENV) -p $(PROJECT_DIR)/cnr -N $1/fix,"set -o pipefail && \
										     cnvkit.py fix $$(<) $$(<<) $$(<<<) -o $$(@)")

endef
 $(foreach sample,$(TUMOR_SAMPLES),\
		$(eval $(call cnvkit-tumor-cnr,$(sample))))
		
define cnvkit-total-copy
cnvkit/plots/log2/$1.pdf : cnvkit/cnr/$1.cnr
	$$(call RUN,-c -s 6G -m 8G -v $(CNVKIT_ENV),"set -o pipefail && \
						     $(RSCRIPT) $(SCRIPTS_DIR)/cnvkit.R \
						     --option 1 \
						     --sample_name $1")

cnvkit/segmented/$1.txt : cnvkit/cnr/$1.cnr
	$$(call RUN,-c -s 6G -m 8G -v $(CNVKIT_ENV),"set -o pipefail && \
						     $(RSCRIPT) $(SCRIPTS_DIR)/cnvkit.R \
						     --option 2 \
						     --sample_name $1")
						     
cnvkit/plots/segmented/$1.pdf : cnvkit/cnr/$1.cnr
	$$(call RUN,-c -s 6G -m 8G -v $(CNVKIT_ENV),"set -o pipefail && \
						     $(RSCRIPT) $(SCRIPTS_DIR)/cnvkit.R \
						     --option 3 \
						     --sample_name $1")
						     
cnvkit/totalcopy/$1.txt : cnvkit/segmented/$1.txt facets/cncf/$1_$2.out
	$$(call RUN,-c -s 6G -m 8G -v $(CNVKIT_ENV),"set -o pipefail && \
						    $(RSCRIPT) $(SCRIPTS_DIR)/cnvkit.R \
						    --option 4 \
						    --sample_name $1_$2")
						    
cnvkit/plots/totalcopy/$1.pdf : cnvkit/cnr/$1.cnr cnvkit/totalcopy/$1.txt facets/cncf/$1_$2.out
	$$(call RUN,-c -s 6G -m 8G -v $(CNVKIT_ENV),"set -o pipefail && \
						    $(RSCRIPT) $(SCRIPTS_DIR)/cnvkit.R \
						    --option 5 \
						    --sample_name $1_$2")
	
endef
$(foreach pair,$(SAMPLE_PAIRS),\
		$(eval $(call cnvkit-total-copy,$(tumor.$(pair)),$(normal.$(pair)))))
		
cnvkit/summary/total_copy.txt : $(foreach sample,$(TUMOR_SAMPLES),cnvkit/totalcopy/$(sample).txt)
	$(call RUN,-n 1 -s 24G -m 32G -v $(CNVKIT_ENV),"set -o pipefail && \
							$(RSCRIPT) $(SCRIPTS_DIR)/cnvkit.R \
							--option 6 \
							--sample_name '$(TUMOR_SAMPLES)'")
							
cnvkit/summary/log2_ratio.txt : $(foreach sample,$(SAMPLES),cnvkit/cnr/$(sample).cnr)
	$(call RUN,-n 1 -s 24G -m 32G -v $(CNVKIT_ENV),"set -o pipefail && \
							$(RSCRIPT) $(SCRIPTS_DIR)/cnvkit.R \
							--option 7 \
							--sample_name '$(SAMPLES)'")



..DUMMY := $(shell mkdir -p version; \
	     python $(CNVKIT_ENV)/bin/cnvkit.py version &> version/cnvkit.txt)
.DELETE_ON_ERROR:
.SECONDARY:
.PHONY: cnv_kit
