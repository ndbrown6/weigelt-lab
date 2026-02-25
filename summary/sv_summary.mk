include weigelt-lab/Makefile.inc

LOGDIR = log/sv_summary.$(NOW)

smry : $(foreach pair,$(SAMPLE_PAIRS),annotate_sv/$(pair)/$(pair).vcf) \
       $(foreach pair,$(SAMPLE_PAIRS),annotate_sv/$(pair)/$(pair).txt) \
       summary/sv_summary.txt

REQUIRED_CALLERS ?= manta
OPTIONAL_CALLERS ?= svaba gridss
CALLERS ?= $(REQUIRED_CALLERS) $(OPTIONAL_CALLERS)
CALLER_MAKEFILES = manta:weigelt-lab/sv_callers/manta_tumor_normal.mk \
		   svaba:weigelt-lab/sv_callers/svaba_tumor_normal.mk \
		   gridss:weigelt-lab/sv_callers/gridss_tumor_normal.mk

get_makefile = $(patsubst $(1):%,%,$(filter $(1):%,$(CALLER_MAKEFILES)))
get_vcf_path = $(1)/$(2)_$(3)/$(2)_$(3).vcf

PROJECT_DIR := $(notdir $(CURDIR))

SURVIVOR_CORES ?= 1
SURVIVOR_MEM_CORE ?= 8G

MAX_DIST = 500
NUM_CALLERS = 2
TYPE = 0
STRAND = 0
MIN_SIZE = 30

define merge-sv-vcf
annotate_sv/$1_$2/$1_$2.vcf : $$(foreach caller,$$(CALLERS),$$(call get_vcf_path,$$(caller),$1,$2))
	$$(call RUN,-c -n $(SURVIVOR_CORES) -s 4G -m $(SURVIVOR_MEM_CORE) -p $(PROJECT_DIR) -N $1_$2/survivor -v $(SURVIVOR_ENV),"set -o pipefail && \
																  mkdir -p annotate_sv/$1_$2 && \
																  rm -f annotate_sv/$1_$2/vcf_list.txt && \
																  $$(foreach caller,$$(CALLERS),echo '$$(call get_vcf_path,$$(caller),$1,$2)' >> annotate_sv/$1_$2/vcf_list.txt &&) \
																  SURVIVOR merge \
																  annotate_sv/$1_$2/vcf_list.txt \
																  $(MAX_DIST) \
																  $(NUM_CALLERS) \
																  $(TYPE) \
																  $(STRAND) \
																  0 \
																  $(MIN_SIZE) \
																  $$(@)")
																	   
annotate_sv/$1_$2/$1_$2.txt : annotate_sv/$1_$2/$1_$2.vcf
	$$(call RUN,-c -n 1 -s 4G -m 8G -p $(PROJECT_DIR) -N $1_$2/AnnotSV -v $(ANNOTATESV_ENV),"set -o pipefail && \
												 rm -f annotate_sv/$1_$2/$1_$2.tsv && \
												 $$(ANNOTATE_SV) \
												 -SVinputFile $$(<) \
												 -outputFile ./annotate_sv/$1_$2/$1_$2.tsv \
												 -genomeBuild GRCh37 && \
												 mv ./annotate_sv/$1_$2/$1_$2.tsv $$(@)")
							       
$$(foreach caller,$$(CALLERS), \
	$$(eval $$(call get_vcf_path,$$(caller),$1,$2) : ; $$(MAKE) -f $$(call get_makefile,$$(caller))))

endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call merge-sv-vcf,$(tumor.$(pair)),$(normal.$(pair)))))
	
summary/sv_summary.txt : $(foreach pair,$(SAMPLE_PAIRS),annotate_sv/$(pair)/$(pair).txt)
	$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/summary -N aggregate,"set -o pipefail && \
										 mkdir -p summary && \
										 $(RSCRIPT) $(SCRIPTS_DIR)/summary/sv_summary.R \
										 --option 1 \
										 --sv_callers '$(CALLERS)' \
										 --sample_name '$(SAMPLE_PAIRS)' \
										 --output $(@)")

..DUMMY := $(shell mkdir -p version; \
	$(SURVIVOR_ENV)/bin/SURVIVOR --version &> version/sv_summary.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: smry clean

clean :
	rm annotate_sv/*/vcf_list.txt
