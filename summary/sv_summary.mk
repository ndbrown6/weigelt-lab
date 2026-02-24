include weigelt-lab/Makefile.inc

LOGDIR = log/sv_summary.$(NOW)

smry : $(foreach pair,$(SAMPLE_PAIRS),annot_sv/$(pair)/$(pair)_jasmine.vcf) \
       $(foreach pair,$(SAMPLE_PAIRS),annot_sv/$(pair)/$(pair)_survivor.vcf) \

REQUIRED_CALLERS ?= manta
OPTIONAL_CALLERS ?= svaba gridss
CALLERS ?= $(REQUIRED_CALLERS) $(OPTIONAL_CALLERS)
CALLER_MAKEFILES = manta:weigelt-lab/sv_callers/manta_tumor_normal.mk \
		   svaba:weigelt-lab/sv_callers/svaba_tumor_normal.mk \
		   gridss:weigelt-lab/sv_callers/gridss_tumor_normal.mk

get_makefile = $(patsubst $(1):%,%,$(filter $(1):%,$(CALLER_MAKEFILES)))
get_vcf_path = $(1)/$(2)_$(3)/$(2)_$(3).vcf

PROJECT_DIR := $(notdir $(CURDIR))

JASMINE_CORES ?= 4
JASMINE_MEM_CORE ?= 8G

SURVIVOR_CORES ?= 1
SURVIVOR_MEM_CORE ?= 8G

define merge-sv-vcf
annot_sv/$1_$2/$1_$2_jasmine.vcf : $$(foreach caller,$$(CALLERS),$$(call get_vcf_path,$$(caller),$1,$2))
	$$(call RUN,-c -n $(JASMINE_CORES) -s 4G -m $(JASMINE_MEM_CORE) -p $(PROJECT_DIR)/annot_sv -N $1_$2/jasmine -v $(JASMINE_ENV),"set -o pipefail && \
																       mkdir -p annot_sv/$1_$2 && \
																       rm -f annot_sv/$1_$2/vcf_list_js.txt && \
																       $$(foreach caller,$$(CALLERS),echo '$$(call get_vcf_path,$$(caller),$1,$2)' >> annot_sv/$1_$2/vcf_list_js.txt &&) \
																       jasmine \
																       file_list=annot_sv/$1_$2/vcf_list_js.txt \
																       out_file=annot_sv/$1_$2/$1_$2_jasmine.vcf \
																       genome_file=$$(REF_FASTA) \
																       --normalize_type \
																       --pre_normalize \
																       --ignore_strand \
																       --ignore_type \
																       max_dist=3000 \
																       min_seq_id=0.2 \
																       min_overlap=0.2 \
																       spec_reads=1 \
																       k_jaccard=5 \
																       threads=$(JASMINE_CORES)")
																    
annot_sv/$1_$2/$1_$2_survivor.vcf : $$(foreach caller,$$(CALLERS),$$(call get_vcf_path,$$(caller),$1,$2))
	$$(call RUN,-c -n $(SURVIVOR_CORES) -s 4G -m $(SURVIVOR_MEM_CORE) -p $(PROJECT_DIR)/annot_sv -N $1_$2/survivor -v $(SURVIVOR_ENV),"set -o pipefail && \
																	   mkdir -p annot_sv/$1_$2 && \
																	   rm -f annot_sv/$1_$2/vcf_list_sv.txt && \
																	   $$(foreach caller,$$(CALLERS),echo '$$(call get_vcf_path,$$(caller),$1,$2)' >> annot_sv/$1_$2/vcf_list_sv.txt &&) \
																	   SURVIVOR merge \
																	   annot_sv/$1_$2/vcf_list_sv.txt \
																	   3000 \
																	   2 \
																	   0 \
																	   0 \
																	   0 \
																	   10 \
																	   $$(@)")
																			    
$$(foreach caller,$$(CALLERS), \
	$$(eval $$(call get_vcf_path,$$(caller),$1,$2) : ; $$(MAKE) -f $$(call get_makefile,$$(caller))))

endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call merge-sv-vcf,$(tumor.$(pair)),$(normal.$(pair)))))


..DUMMY := $(shell mkdir -p version; \
	$(JASMINE_ENV)/bin/jasmine --version &> version/sv_summary.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: smry clean

clean :
	rm annot_sv/*/vcf_list_*.txt
