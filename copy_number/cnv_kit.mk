include weigelt-lab/Makefile.inc

LOGDIR ?= log/cnv_kit.$(NOW)

cnv_kit : cnv_kit/on_target.bed \
	  cnv_kit/off_target.bed \
	  $(foreach sample,$(TUMOR_SAMPLES),cnv_kit/cnn/tumor/$(sample).targetcoverage.cnn) \
	  $(foreach sample,$(TUMOR_SAMPLES),cnv_kit/cnn/tumor/$(sample).antitargetcoverage.cnn) \
	  $(foreach sample,$(NORMAL_SAMPLES),cnv_kit/cnn/normal/$(sample).targetcoverage.cnn) \
	  $(foreach sample,$(NORMAL_SAMPLES),cnv_kit/cnn/normal/$(sample).antitargetcoverage.cnn) \
	  cnv_kit/reference.cnr \
	  $(foreach sample,$(TUMOR_SAMPLES),cnv_kit/log2/$(sample).txt) \
	  $(foreach set,$(SAMPLE_SETS),cnv_kit/segmented/$(set).txt) \
	  $(foreach set,$(SAMPLE_SETS),cnv_kit/totalcopy/$(set).txt) \
	  cnv_kit/summary/copy_smry.txt \
	  cnv_kit/summary/log2_smry.txt \
	  $(foreach sample,$(TUMOR_SAMPLES),cnv_kit/plot/log2/$(sample).pdf) \
	  $(foreach sample,$(TUMOR_SAMPLES),cnv_kit/plot/segmented/$(sample).pdf) \
	  $(foreach sample,$(TUMOR_SAMPLES),cnv_kit/plot/totalcopy/$(sample).pdf)

REF_FLAT ?= ~/share/lib/resource_files/refFlat_ensembl.v75.txt
EXCLUDE_BED ?= ~/share/lib/bed_files/access-excludes.b37.bed

PROJECT_DIR := $(notdir $(CURDIR))

cnv_kit/on_target.bed : $(TARGETS_FILE)
	$(call RUN,-c -n 4 -s 6G -m 8G -v $(CNVKIT_ENV) -p $(PROJECT_DIR) -N on_target,"set -o pipefail && \
											cnvkit.py target $(<) \
											--annotate $(REF_FLAT) \
											--split -o $(@)")

cnv_kit/off_target.bed : cnv_kit/on_target.bed
	$(call RUN,-c -n 4 -s 6G -m 8G -v $(CNVKIT_ENV) -p $(PROJECT_DIR) -N off_target,"set -o pipefail && \
											 cnvkit.py antitarget $(<) \
											 -g $(EXCLUDE_BED) \
											 -o $(@)")

define cnvkit-tumor-cnn
cnv_kit/cnn/tumor/$1.targetcoverage.cnn : bam/$1.bam cnv_kit/on_target.bed
	$$(call RUN,-c -n 4 -s 6G -m 8G -v $(CNVKIT_ENV) -p $(PROJECT_DIR)/cnn -N $1/on_target,"set -o pipefail && \
												cnvkit.py coverage -p 4 -q 0 $$(<) $$(<<) -o $$(@)")

cnv_kit/cnn/tumor/$1.antitargetcoverage.cnn : bam/$1.bam cnv_kit/off_target.bed
	$$(call RUN,-c -n 4 -s 6G -m 8G -v $(CNVKIT_ENV) -p $(PROJECT_DIR)/cnn -N $1/off_target,"set -o pipefail && \
												 cnvkit.py coverage -p 4 -q 0 $$(<) $$(<<) -o $$(@)")
endef
 $(foreach sample,$(TUMOR_SAMPLES),\
		$(eval $(call cnvkit-tumor-cnn,$(sample))))
		
define cnvkit-normal-cnn
cnv_kit/cnn/normal/$1.targetcoverage.cnn : bam/$1.bam cnv_kit/on_target.bed
	$$(call RUN,-c -n 4 -s 6G -m 8G -v $(CNVKIT_ENV) -p $(PROJECT_DIR)/cnn -N $1/on_target,"set -o pipefail && \
												cnvkit.py coverage -p 4 -q 0 $$(<) $$(<<) -o $$(@)")

cnv_kit/cnn/normal/$1.antitargetcoverage.cnn : bam/$1.bam bam/$1.bam cnv_kit/off_target.bed
	$$(call RUN,-c -n 4 -s 6G -m 8G -v $(CNVKIT_ENV) -p $(PROJECT_DIR)/cnn -N $1/off_target,"set -o pipefail && \
												 cnvkit.py coverage -p 4 -q 0 $$(<) $$(<<) -o $$(@)")
endef
 $(foreach sample,$(NORMAL_SAMPLES),\
		$(eval $(call cnvkit-normal-cnn,$(sample))))

cnv_kit/reference.cnr : $(foreach sample,$(NORMAL_SAMPLES),cnv_kit/cnn/normal/$(sample).targetcoverage.cnn) $(foreach sample,$(NORMAL_SAMPLES),cnv_kit/cnn/normal/$(sample).antitargetcoverage.cnn)
	$(call RUN,-n 1 -s 24G -m 32G -v $(CNVKIT_ENV) -p $(PROJECT_DIR) -N reference,"set -o pipefail && \
										       sleep 30 && \
										       cnvkit.py reference cnv_kit/cnn/normal/*.cnn -f $(REF_FASTA) --no-edge -o $(@)")

define cnvkit-tumor-cnr
cnv_kit/log2/$1.txt : cnv_kit/cnn/tumor/$1.targetcoverage.cnn cnv_kit/cnn/tumor/$1.antitargetcoverage.cnn cnv_kit/reference.cnr
	$$(call RUN,-c -s 6G -m 8G -v $(CNVKIT_ENV) -p $(PROJECT_DIR)/log2 -N $1/fix,"set -o pipefail && \
										      cnvkit.py fix $$(<) $$(<<) $$(<<<) -o $$(@)")

endef
 $(foreach sample,$(TUMOR_SAMPLES),\
		$(eval $(call cnvkit-tumor-cnr,$(sample))))
		
define aggregate-copy-number
cnv_kit/segmented/$1.txt : $(foreach sample,$(TUMOR_SAMPLES),cnv_kit/log2/$(sample).txt)
	$$(call RUN,-c -n 1 -s 6G -m 8G -v $(CNVKIT_ENV) -p $(PROJECT_DIR) -N aggregate/log2,"set -o pipefail && \
											      $$(RSCRIPT) $(SCRIPTS_DIR)/copy_number/cnv_kit.R \
											      --option 1 \
											      --file_in $$(^) \
											      --file_out $$(@)")

cnv_kit/totalcopy/$1.txt : cnv_kit/segmented/$1.txt
	$$(call RUN,-c -n 1 -s 6G -m 8G -v $(CNVKIT_ENV) -p $(PROJECT_DIR) -N aggregate/segments,"set -o pipefail && \
												  $$(RSCRIPT) $(SCRIPTS_DIR)/copy_number/cnv_kit.R \
												  --option 2 \
												  --file_in $$(<) \
												  --file_out $$(@)")

endef
$(foreach set,$(SAMPLE_SETS),\
		$(eval $(call aggregate-copy-number,$(set))))

cnv_kit/summary/log2_smry.txt : $(foreach sample,$(SAMPLES),cnv_kit/log2/$(sample).txt)
	$(call RUN,-n 1 -s 24G -m 36G -v $(CNVKIT_ENV) -p $(PROJECT_DIR) -N aggregate/log2,"set -o pipefail && \
											    $$(RSCRIPT) $(SCRIPTS_DIR)/cnvkit.R \
											    --option 3 \
											    --file_in $(^) \
											    --file_out $(@)")

cnv_kit/summary/copy_smry.txt : $(foreach set,$(SAMPLE_SETS),cnv_kit/totalcopy/$(set).txt)
	$(call RUN,-n 1 -s 12G -m 24G -v $(CNVKIT_ENV) -p $(PROJECT_DIR) -N aggregate/sets,"set -o pipefail && \
											    $(RSCRIPT) $(SCRIPTS_DIR)/copy_number/cnv_kit.R \
											    --option 4 \
											    --file_in $(^) \
											    --file_out $(@)")

define plot-tumor
cnv_kit/plot/log2/$1.pdf : cnv_kit/summary/log2_smry.txt
	$$(call RUN,-c -s 12G -m 24G -v $(CNVKIT_ENV) -p $(PROJECT_DIR)/plot -N $1/log2,"set -o pipefail && \
										         $$(RSCRIPT) $(SCRIPTS_DIR)/copy_number/cnv_kit.R \
											 --option 5 \
											 --sample_name $1 \
											 --file_in $$(<) \
											 --file_out $$(@)")

cnv_kit/plots/segmented/$1.pdf : cnv_kit/summary/log2_smry.txt cnv_kit/summary/copy_smry.txt
	$$(call RUN,-c -s 24G -m 36G -v $(CNVKIT_ENV) -p $(PROJECT_DIR)/plot -N $1/segmented,"set -o pipefail && \
											      $$(RSCRIPT) $(SCRIPTS_DIR)/copy_number/cnv_kit.R \
											      --option 6 \
											      --sample_name $1 \
											      --file_in $$(^) \
											      --file_out $$(@)")
						     
cnv_kit/plots/totalcopy/$1.pdf : cnv_kit/summary/log2_smry.txt cnv_kit/summary/copy_smry.txt
	$$(call RUN,-c -s 24G -m 36G -v $(CNVKIT_ENV) -p $(PROJECT_DIR)/plot -N $1/totalcopy,"set -o pipefail && \
											      $$(RSCRIPT) $(SCRIPTS_DIR)/copy_number/cnv_kit.R \
											      --option 7 \
											      --sample_name $1 \
											      --file_in $$(^) \
											      --file_out $$(@)")

endef
 $(foreach sample,$(TUMOR_SAMPLES),\
		$(eval $(call plot-tumor,$(sample))))


..DUMMY := $(shell mkdir -p version; \
         python $(CNVKIT_ENV)/bin/cnvkit.py version &> version/cnv_kit.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
	rm -f cnv_kit/on_target.bed && \
	rm -f cnv_kit/off_target.bed && \
	rm -f cnv_kit/cnn/*/*.targetcoverage.cnn && \
	rm -f cnv_kit/cnn/*/*.antitargetcoverage.cnn && \
	rm -f cnv_kit/reference.cnr