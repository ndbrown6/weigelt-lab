include weigelt-lab/Makefile.inc

LOGDIR ?= log/cnv_kit.$(NOW)

cnvkit : $(foreach sample,$(TUMOR_SAMPLES),cnv_kit/$(sample)/$(sample).txt) \
		 $(foreach sample,$(NORMAL_SAMPLES),cnv_kit/$(sample)/$(sample).txt)
#		 $(foreach set,$(SAMPLE_SETS),cnv_kit/normalized_log2/$(set).txt) \
#		 $(foreach set,$(SAMPLE_SETS),cnv_kit/normalized_log2/$(set).tsv) \
#		 cnv_kit/summary/aggregated-log2.txt \
#		 cnv_kit/summary/aggregated-segmented.txt
	 
MAX_SIGMA ?= 0.25
WINSORIZE_TAU ?= 2.5
WINSORIZE_K ?= 25
PCF_GAMMA ?= 150

REF_FLAT ?= ~/share/lib/resource_files/refFlat_ensembl.v75.txt
EXCLUDE_BED ?= ~/share/lib/bed_files/access-excludes.b37.bed

PROJECT_DIR := $(notdir $(CURDIR))

cnv_kit/bed_files/on_target.bed : $(TARGETS_FILE)
	$(call RUN,-c -n 4 -s 2G -m 4G -v $(CNVKIT_ENV) -p $(PROJECT_DIR) -N on_target,"set -o pipefail && \
																					mkdir -p cnv_kit/bed_files && \
																					cnvkit.py target $(<) \
																					--annotate $(REF_FLAT) \
																					--split -o $(@)")

cnv_kit/bed_files/off_target.bed : cnv_kit/bed_files/on_target.bed
	$(call RUN,-c -n 4 -s 2G -m 4G -v $(CNVKIT_ENV) -p $(PROJECT_DIR) -N off_target,"set -o pipefail && \
																					 mkdir -p cnv_kit/bed_files && \
																					 cnvkit.py antitarget $(<) \
																					 -g $(EXCLUDE_BED) \
																					 -o $(@)")

define cnvkit-tumor-cnn
cnv_kit/read_counts/T/$1.targetcoverage.cnn : bam/$1.bam cnv_kit/bed_files/on_target.bed
	$$(call RUN,-c -n 4 -s 2G -m 4G -v $(CNVKIT_ENV) -p $(PROJECT_DIR)/read_counts -N $1/on_target,"set -o pipefail && \
																									mkdir -p cnv_kit/read_counts/T && \
																									cnvkit.py coverage -p 4 -q 0 $$(<) $$(<<) -o $$(@)")

cnv_kit/read_counts/T/$1.antitargetcoverage.cnn : bam/$1.bam cnv_kit/bed_files/off_target.bed
	$$(call RUN,-c -n 4 -s 2G -m 4G -v $(CNVKIT_ENV) -p $(PROJECT_DIR)/read_counts -N $1/off_target,"set -o pipefail && \
																									 mkdir -p cnv_kit/read_counts/T && \
																									 cnvkit.py coverage -p 4 -q 0 $$(<) $$(<<) -o $$(@)")
endef
 $(foreach sample,$(TUMOR_SAMPLES),\
		$(eval $(call cnvkit-tumor-cnn,$(sample))))
		
define cnvkit-normal-cnn
cnv_kit/read_counts/N/$1.targetcoverage.cnn : bam/$1.bam cnv_kit/bed_files/on_target.bed
	$$(call RUN,-c -n 4 -s 2G -m 4G -v $(CNVKIT_ENV) -p $(PROJECT_DIR)/read_counts -N $1/on_target,"set -o pipefail && \
																									mkdir -p cnv_kit/read_counts/N && \
																									cnvkit.py coverage -p 4 -q 0 $$(<) $$(<<) -o $$(@)")

cnv_kit/read_counts/N/$1.antitargetcoverage.cnn : bam/$1.bam bam/$1.bam cnv_kit/bed_files/off_target.bed
	$$(call RUN,-c -n 4 -s 2G -m 4G -v $(CNVKIT_ENV) -p $(PROJECT_DIR)/read_counts -N $1/off_target,"set -o pipefail && \
																									 mkdir -p cnv_kit/read_counts/N && \
																									 cnvkit.py coverage -p 4 -q 0 $$(<) $$(<<) -o $$(@)")
endef
 $(foreach sample,$(NORMAL_SAMPLES),\
		$(eval $(call cnvkit-normal-cnn,$(sample))))

cnv_kit/read_counts/reference.cnr : $(foreach sample,$(NORMAL_SAMPLES),cnv_kit/read_counts/N/$(sample).targetcoverage.cnn) $(foreach sample,$(NORMAL_SAMPLES),cnv_kit/read_counts/N/$(sample).antitargetcoverage.cnn)
	$(call RUN,-c -n 1 -s 12G -m 24G -v $(CNVKIT_ENV) -p $(PROJECT_DIR) -N reference,"set -o pipefail && \
																					  sleep 30 && \
																					  cnvkit.py reference cnv_kit/read_counts/N/*.cnn -f $(REF_FASTA) --no-edge -o $(@)")

define cnvkit-tumor-cnr
cnv_kit/$1/$1.txt : cnv_kit/read_counts/T/$1.targetcoverage.cnn cnv_kit/read_counts/T/$1.antitargetcoverage.cnn cnv_kit/read_counts/reference.cnr
	$$(call RUN,-c -n 1 -s 4G -m 8G -v $(CNVKIT_ENV) -p $(PROJECT_DIR)/normalized_log2 -N $1/fix,"set -o pipefail && \
																								  mkdir -p cnv_kit/$1 && \
																							      cnvkit.py fix $$(<) $$(<<) $$(<<<) -o $$(@)")

endef
 $(foreach sample,$(TUMOR_SAMPLES),\
		$(eval $(call cnvkit-tumor-cnr,$(sample))))
		
define cnvkit-normal-cnr
cnv_kit/$1/$1.txt : cnv_kit/read_counts/N/$1.targetcoverage.cnn cnv_kit/read_counts/N/$1.antitargetcoverage.cnn cnv_kit/read_counts/reference.cnr
	$$(call RUN,-c -n 1 -s 4G -m 8G -v $(CNVKIT_ENV) -p $(PROJECT_DIR)/normalized_log2 -N $1/fix,"set -o pipefail && \
																								  mkdir -p cnv_kit/$1 && \
																							      cnvkit.py fix $$(<) $$(<<) $$(<<<) -o $$(@)")

endef
 $(foreach sample,$(NORMAL_SAMPLES),\
		$(eval $(call cnvkit-normal-cnr,$(sample))))
		
define aggregate-copy-number
cnv_kit/normalized_log2/$1.txt : $(foreach sample,$(TUMOR_SAMPLES),cnv_kit/normalized_log2/$(sample).txt)
	$$(call RUN,-c -n 1 -s 4G -m 6G -v $(COPYNUMBER_ENV) -p $(PROJECT_DIR) -N aggregate/log2/$1,"set -o pipefail && \
																							     $$(RSCRIPT) $(SCRIPTS_DIR)/copy_number/cnv_kit.R \
																							     --option 1 \
																							     --tumor_sample '$(tumors.$1)' \
																							     --normal_sample '$(NORMAL_SAMPLES)' \
																							     --file_out $$(@) \
																							     --sigma $(MAX_SIGMA)")

cnv_kit/normalized_log2/$1.tsv : cnv_kit/normalized_log2/$1.txt
	$$(call RUN,-c -n 1 -s 4G -m 6G -v $(COPYNUMBER_ENV) -p $(PROJECT_DIR) -N aggregate/segmented/$1,"set -o pipefail && \
																									  $$(RSCRIPT) $(SCRIPTS_DIR)/copy_number/cnv_kit.R \
																									  --option 2 \
																									  --file_in $$(<) \
																									  --file_out $$(@) \
																									  --tumor_sample '$(tumors.$1)' \
																									  --tau $(WINSORIZE_TAU) \
																									  --k $(WINSORIZE_K)\
																									  --gamma $(PCF_GAMMA)")

endef
$(foreach set,$(SAMPLE_SETS),\
		$(eval $(call aggregate-copy-number,$(set))))

cnv_kit/summary/aggregated-log2.txt : $(foreach set,$(SAMPLE_SETS),cnv_kit/normalized_log2/$(set).txt)
	$(call RUN,-c -n 1 -s 24G -m 36G -v $(COPYNUMBER_ENV) -p $(PROJECT_DIR) -N aggregate/log2/sets,"set -o pipefail && \
																									$(RSCRIPT) $(SCRIPTS_DIR)/copy_number/cnv_kit.R \
																									--option 3 \
																									--file_in '$(^)' \
																									--file_out $(@)")

cnv_kit/summary/aggregated-segmented.txt : $(foreach set,$(SAMPLE_SETS),cnv_kit/normalized_log2/$(set).tsv)
	$(call RUN,-c -n 1 -s 8G -m 16G -v $(COPYNUMBER_ENV) -p $(PROJECT_DIR) -N aggregate/segmented/sets,"set -o pipefail && \
																									    $(RSCRIPT) $(SCRIPTS_DIR)/copy_number/cnv_kit.R \
																									    --option 4 \
																									    --file_in '$(^)' \
																									    --file_out $(@)")

..DUMMY := $(shell mkdir -p version; \
	python $(CNVKIT_ENV)/bin/cnvkit.py version &> version/cnv_kit.txt; \
	$(COPYNUMBER_ENV)/bin/R --version >> version/cnv_kit.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
	rm -rf cnv_kit/bed_files && \
	rm -rf cnv_kit/read_counts
