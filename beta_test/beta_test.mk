include weigelt-lab/Makefile.inc

LOGDIR = log/beta_test.$(NOW)

beta_test : $(foreach sample,$(SAMPLES),beta_test/$(sample).txt)

define beta-test
beta_test/$1.txt :
	$$(call RUN,-n 4 -s 4G -m 9G,"set -o pipefail && \
				      mkdir -p beta_test/ && \
				      echo $1 > $$(@)")

endef
$(foreach sample,$(SAMPLES),\
		$(eval $(call beta-test,$(sample))))

..DUMMY := $(shell mkdir -p version; \
	     ~/share/env/weigelt-lab-0.0.1/bin/R --version >> version/beta_test.txt;)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: beta_test
