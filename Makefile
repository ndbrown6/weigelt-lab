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
# Summary
#==================================================

TARGETS += mutation_summary
mutation_summary :
	$(call RUN_MAKE,weigelt-lab/summary/mutation_summary.mk) && \
	$(MAKE) -f weigelt-lab/summary/mutation_summary.mk clean
	
TARGETS += sv_summary
sv_summary :
	$(call RUN_MAKE,weigelt-lab/summary/sv_summary.mk) && \
	$(MAKE) -f weigelt-lab/summary/sv_summary.mk clean
	
TARGETS += fusion_summary
fusion_summary :
	$(call RUN_MAKE,weigelt-lab/summary/fusion_summary.mk)

#==================================================
# FASTQ aligners
#==================================================

TARGETS += align_impact_fastq
align_impact_fastq :
	$(call RUN_MAKE,weigelt-lab/fastq_aligners/align_impact_fastq.mk) && \
	$(MAKE) -f weigelt-lab/fastq_aligners/align_impact_fastq.mk clean
	
TARGETS += align_exome_fastq
align_exome_fastq :
	$(call RUN_MAKE,weigelt-lab/fastq_aligners/align_exome_fastq.mk) && \
	$(MAKE) -f weigelt-lab/fastq_aligners/align_exome_fastq.mk clean
	
TARGETS += align_genome_fastq
align_genome_fastq :
	$(call RUN_MAKE,weigelt-lab/fastq_aligners/align_genome_fastq.mk) && \
	$(MAKE) -f weigelt-lab/fastq_aligners/align_genome_fastq.mk clean
	
TARGETS += align_rnaseq_fastq
align_rnaseq_fastq :
	$(call RUN_MAKE,weigelt-lab/fastq_aligners/align_rnaseq_fastq.mk) && \
	$(MAKE) -f weigelt-lab/fastq_aligners/align_rnaseq_fastq.mk clean
	
#==================================================
# Variant callers
#==================================================

TARGETS += mutect_tumor_normal
mutect_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/variant_callers/mutect_tumor_normal.mk) && \
	$(MAKE) -f weigelt-lab/variant_callers/mutect_tumor_normal.mk clean
	
TARGETS += varscan_tumor_normal
varscan_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/variant_callers/varscan_tumor_normal.mk) && \
	$(MAKE) -f weigelt-lab/variant_callers/varscan_tumor_normal.mk clean
	
TARGETS += strelka_tumor_normal
strelka_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/variant_callers/strelka_tumor_normal.mk) && \
	$(MAKE) -f weigelt-lab/variant_callers/strelka_tumor_normal.mk clean
	
TARGETS += scalpel_tumor_normal
scalpel_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/variant_callers/scalpel_tumor_normal.mk) && \
	$(MAKE) -f weigelt-lab/variant_callers/scalpel_tumor_normal.mk clean
	
TARGETS += platypus_tumor_normal
platypus_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/variant_callers/platypus_tumor_normal.mk) && \
	$(MAKE) -f weigelt-lab/variant_callers/platypus_tumor_normal.mk clean
	
#==================================================
# Copy number aberrations
#==================================================

TARGETS += facets_suite
facets_suite :
	$(call RUN_MAKE,weigelt-lab/copy_number/facets_suite.mk) && \
	$(MAKE) -f weigelt-lab/copy_number/facets_suite.mk clean
	
TARGETS += cnv_kit
cnv_kit :
	$(call RUN_MAKE,weigelt-lab/copy_number/cnv_kit.mk) && \
	$(MAKE) -f weigelt-lab/copy_number/cnv_kit.mk clean
	
#==================================================
# RNA expression
#==================================================

TARGETS += kallisto_quant
kallisto_quant :
	$(call RUN_MAKE,weigelt-lab/rna_seq/kallisto_quant.mk) && \
	$(MAKE) -f weigelt-lab/rna_seq/kallisto_quant.mk clean
	
TARGETS += salmon_quant
salmon_quant :
	$(call RUN_MAKE,weigelt-lab/rna_seq/salmon_quant.mk) && \
	$(MAKE) -f weigelt-lab/rna_seq/salmon_quant.mk clean
	
#==================================================
# DNA structural variant callers
#==================================================	

TARGETS += manta_tumor_normal
manta_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/sv_callers/manta_tumor_normal.mk) && \
	$(MAKE) -f weigelt-lab/sv_callers/manta_tumor_normal.mk clean
	
TARGETS += svaba_tumor_normal
svaba_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/sv_callers/svaba_tumor_normal.mk) && \
	$(MAKE) -f weigelt-lab/sv_callers/svaba_tumor_normal.mk clean
	
TARGETS += gridss_tumor_normal
gridss_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/sv_callers/gridss_tumor_normal.mk) && \
	$(MAKE) -f weigelt-lab/sv_callers/gridss_tumor_normal.mk clean
	
TARGETS += delly_tumor_normal
delly_tumor_normal :
	$(call RUN_MAKE,weigelt-lab/sv_callers/delly_tumor_normal.mk) && \
	$(MAKE) -f weigelt-lab/sv_callers/delly_tumor_normal.mk clean
	
#==================================================
# RNA fusion callers
#==================================================

TARGETS += arriba_fusion
arriba_fusion :
	$(call RUN_MAKE,weigelt-lab/sv_callers/arriba_fusion.mk) && \
	$(MAKE) -f weigelt-lab/sv_callers/arriba_fusion.mk clean
	
TARGETS += star_fusion
star_fusion :
	$(call RUN_MAKE,weigelt-lab/sv_callers/star_fusion.mk) && \
	$(MAKE) -f weigelt-lab/sv_callers/star_fusion.mk clean

TARGETS += fusion_catcher
fusion_catcher :
	$(call RUN_MAKE,weigelt-lab/sv_callers/fusion_catcher.mk) && \
	$(MAKE) -f weigelt-lab/sv_callers/fusion_catcher.mk clean
	
#==================================================
# VCF tools
#==================================================

TARGETS += annotate_vcf_maf
annotate_vcf_maf :
	$(call RUN_MAKE,weigelt-lab/vcf_tools/annotate_vcf_maf.mk)
	
TARGETS += annotate_maf_vcf
annotate_maf_vcf :
	$(call RUN_MAKE,weigelt-lab/vcf_tools/annotate_maf_vcf.mk)
	
#==================================================
# BAM tools
#==================================================

TARGETS += idx_metrics
idx_metrics :
	$(call RUN_MAKE,weigelt-lab/bam_tools/idx_metrics.mk)

TARGETS += aln_metrics
aln_metrics :
	$(call RUN_MAKE,weigelt-lab/bam_tools/aln_metrics.mk)

TARGETS += insert_metrics
insert_metrics :
	$(call RUN_MAKE,weigelt-lab/bam_tools/insert_metrics.mk)

TARGETS += oxog_metrics
oxog_metrics :
	$(call RUN_MAKE,weigelt-lab/bam_tools/oxog_metrics.mk)

TARGETS += gc_metrics
gc_metrics :
	$(call RUN_MAKE,weigelt-lab/bam_tools/gc_metrics.mk)

TARGETS += hs_metrics
hs_metrics :
	$(call RUN_MAKE,weigelt-lab/bam_tools/hs_metrics.mk)

TARGETS += dup_metrics
dup_metrics :
	$(call RUN_MAKE,weigelt-lab/bam_tools/dup_metrics.mk)
	
TARGETS += wgs_metrics
wgs_metrics :
	$(call RUN_MAKE,weigelt-lab/bam_tools/wgs_metrics.mk)
	
TARGETS += rnaseq_metrics
rnaseq_metrics :
	$(call RUN_MAKE,weigelt-lab/bam_tools/rnaseq_metrics.mk)
	

.PHONY : $(TARGETS)
