ifndef CONFIG_INC

REF ?= b37
SEQ_PLATFORM ?= illumina

# conda
WEIGELT_LAB_ENV ?= $(HOME)/share/env/weigelt-lab-0.0.1

# paths
SCRIPTS_DIR ?= weigelt-lab/dodo-cloning-kit
TMPDIR ?= $(HOME)/share/usr/$(USER)/tmp

endif
CONFIG_INC = true
