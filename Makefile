ifneq ("$(wildcard config.inc)", "")
	include config.inc
endif
ifneq ("$(wildcard project_config.inc)", "")
	include project_config.inc
endif
include weigelt-lab/config/config.inc

export

NUM_ATTEMPTS ?= 10
NOW := $(shell date +"%F")
MAKELOG = log/$(@).$(NOW).log

USE_CLUSTER ?= true
QMAKE = weigelt-lab/dodo-cloning-kit/runtime/qmake.pl -n $@.$(NOW) $(if $(SLACK_CHANNEL),-c $(SLACK_CHANNEL)) -r $(NUM_ATTEMPTS) -m -s -- make
NUM_JOBS ?= 100

define RUN_QMAKE
$(QMAKE) -e -f $1 -j $2 $(TARGET) && \
	mkdir -p completed_tasks && \
	touch completed_tasks/$@
endef

RUN_MAKE = $(if $(findstring false,$(USE_CLUSTER))$(findstring n,$(MAKEFLAGS)),+$(MAKE) -f $1,$(call RUN_QMAKE,$1,$(NUM_JOBS)))

#==================================================
# FASTQ aligners
#==================================================

TARGETS += align_impact_fastq
align_impact_fastq :
	$(call RUN_MAKE,weigelt-lab/fastq_aligners/align_impact_fastq.mk)
	
TARGETS += align_exome_fastq
align_exome_fastq :
	$(call RUN_MAKE,weigelt-lab/fastq_aligners/align_exome_fastq.mk)
	
TARGETS += align_genome_fastq
align_genome_fastq :
	$(call RUN_MAKE,weigelt-lab/fastq_aligners/align_genome_fastq.mk)
	
TARGETS += align_rnaseq_fastq
align_rnaseq_fastq :
	$(call RUN_MAKE,weigelt-lab/fastq_aligners/align_rnaseq_fastq.mk)
	
#==================================================
# Variant callers
#==================================================

TARGETS += mutect_tumor_normal
mutect_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/variant_callers/mutect_tumor_normal.mk)
	
TARGETS += varscan_tumor_normal
varscan_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/variant_callers/varscan_tumor_normal.mk)
	
TARGETS += strelka_tumor_normal
strelka_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/variant_callers/strelka_tumor_normal.mk)
	
TARGETS += scalpel_tumor_normal
scalpel_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/variant_callers/scalpel_tumor_normal.mk)
	
TARGETS += platypus_tumor_normal
platypus_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/variant_callers/platypus_tumor_normal.mk)
	
#==================================================
# DNA structural variant callers
#==================================================	

TARGETS += manta_tumor_normal
manta_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/sv_callers/manta_tumor_normal.mk)
	
TARGETS += svaba_tumor_normal
svaba_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/sv_callers/svaba_tumor_normal.mk)
	
TARGETS += gridss_tumor_normal
gridss_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/sv_callers/gridss_tumor_normal.mk)
	
TARGETS += manta_tumor_only
manta_tumor_only :
	$(call RUN_MAKE,weigelt-lab/sv_callers/manta_tumor_only.mk)
	
TARGETS += svaba_tumor_only
svaba_tumor_only :
	$(call RUN_MAKE,weigelt-lab/sv_callers/svaba_tumor_only.mk)
	
TARGETS += gridss_tumor_only
gridss_tumor_only :
	$(call RUN_MAKE,weigelt-lab/sv_callers/gridss_tumor_only.mk)
	
#==================================================
# RNA structural variant/fusion callers
#==================================================

TARGETS += star_fusion
star_fusion :
	$(call RUN_MAKE,modules/sv_callers/star_fusion.mk)

TARGETS += fusion_catcher
fusion_catcher :
	$(call RUN_MAKE,modules/sv_callers/fusion_catcher.mk)
	
TARGETS += arriba
arriba :
	$(call RUN_MAKE,modules/sv_callers/arriba.mk)
	

.PHONY : $(TARGETS)
