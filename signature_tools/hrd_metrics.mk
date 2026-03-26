include weigelt-lab/Makefile.inc

LOGDIR ?= log/hrd_metrics.$(NOW)

smry : $(foreach pair,$(SAMPLE_PAIRS),hrd_metrics/$(pair)/FGA.txt) \
	   $(foreach pair,$(SAMPLE_PAIRS),hrd_metrics/$(pair)/LST.txt) \
	   $(foreach pair,$(SAMPLE_PAIRS),hrd_metrics/$(pair)/ntAI.txt) \
	   $(foreach pair,$(SAMPLE_PAIRS),hrd_metrics/$(pair)/MS.txt) \
	   hrd_metrics/hrd_summary.txt

PROJECT_DIR := $(notdir $(CURDIR))

define fraction-genome-altered
hrd_metrics/$1_$2/FGA.txt : facets_suite/$1_$2/$1_$2_purity.Rdata
	$$(call RUN,-n 1 -s 3G -m 6G -p $(PROJECT_DIR)/fga -N $1/$2,"set -o pipefail && \
																 mkdir -p hrd_metrics/$1_$2/ && \
																 $(RSCRIPT) $(SCRIPTS_DIR)/signature_tools/hrd_metrics.R \
																 --option 1 \
																 --sample_name $1_$2 \
																 --file_in $$(<) \
																 --file_out $$(@)")

endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call fraction-genome-altered,$(tumor.$(pair)),$(normal.$(pair)))))
		
define lst-score
hrd_metrics/$1_$2/LST.txt : facets_suite/$1_$2/$1_$2_purity.Rdata
	$$(call RUN,-n 1 -s 3G -m 6G -p $(PROJECT_DIR)/lst -N $1/$2,"set -o pipefail && \
																 mkdir -p hrd_metrics/$1_$2/ && \
																 $(RSCRIPT) $(SCRIPTS_DIR)/signature_tools/hrd_metrics.R \
																 --option 2 \
																 --sample_name $1_$2 \
																 --file_in $$(<) \
																 --file_out $$(@)")

endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call lst-score,$(tumor.$(pair)),$(normal.$(pair)))))
		
define ntai-score
hrd_metrics/$1_$2/ntAI.txt : facets_suite/$1_$2/$1_$2_purity.Rdata
	$$(call RUN,-n 1 -s 3G -m 6G -p $(PROJECT_DIR)/ntAI -N $1/$2,"set -o pipefail && \
																  mkdir -p hrd_metrics/$1_$2/ && \
																  $(RSCRIPT) $(SCRIPTS_DIR)/signature_tools/hrd_metrics.R \
																  --option 3 \
																  --sample_name $1_$2 \
																  --file_in $$(<) \
																  --file_out $$(@)")

endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call ntai-score,$(tumor.$(pair)),$(normal.$(pair)))))
		
define myriad-score
hrd_metrics/$1_$2/MS.txt : facets_suite/$1_$2/$1_$2_purity.Rdata
	$$(call RUN,-n 1 -s 3G -m 6G -p $(PROJECT_DIR)/MS -N $1/$2,"set -o pipefail && \
																mkdir -p hrd_metrics/$1_$2/ && \
																$(RSCRIPT) $(SCRIPTS_DIR)/signature_tools/hrd_metrics.R \
																--option 4 \
																--sample_name $1_$2 \
																--file_in $$(<) \
																--file_out $$(@)")

endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call myriad-score,$(tumor.$(pair)),$(normal.$(pair)))))

hrd_metrics/hrd_summary.txt : $(foreach pair,$(SAMPLE_PAIRS),hrd_metrics/$(pair)/FGA.txt) \
							  $(foreach pair,$(SAMPLE_PAIRS),hrd_metrics/$(pair)/LST.txt) \
							  $(foreach pair,$(SAMPLE_PAIRS),hrd_metrics/$(pair)/ntAI.txt) \
							  $(foreach pair,$(SAMPLE_PAIRS),hrd_metrics/$(pair)/MS.txt)
	$(call RUN,-n 1 -s 4G -m 8G -p $(PROJECT_DIR) -N aggregate,"set -o pipefail && \
															    $(RSCRIPT) $(SCRIPTS_DIR)/signature_tools/hrd_metrics.R \
															    --option 5 \
															    --sample_name '$(SAMPLE_PAIRS)' \
															    --file_out $(@)")
							 
..DUMMY := $(shell mkdir -p version; \
	R --version &> version/hrd_metrics.txt;)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: smry clean

clean :
