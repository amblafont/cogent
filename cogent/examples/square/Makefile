#
# Copyright 2017, NICTA
#
# This software may be distributed and modified according to the terms of
# the GNU General Public License version 2. Note that NO WARRANTY is provided.
# See "LICENSE_GPLv2.txt" for details.
#
# @TAG(NICTA_GPL)
#

NAME=square

REPO="../../.."

SRC=square.cogent
OUTPUT=square # $(SRC:.cogent=-gen)
COUTPUT=$(addsuffix .c, $(OUTPUT))
HOUTPUT=$(addsuffix .h, $(OUTPUT))

STDGUM=$(shell cogent --stdgum-dir)

ACFILES=main.ac

PP=$(ACFILES:.ac=_pp.ac)
PPINFER=$(ACFILES:.ac=_pp_inferred.c)

OBJ=$(PPINFER:.c=.o)

CFLAGS=-I. -I$(STDGUM) -I$(STDGUM)/gum/anti -std=gnu99  # -I../plat/console 

.PHONY: default clean gen-anti
.SECONDARY:

default: all

all: gen-anti $(OBJ) gen-verif
	$(CC) -o $(NAME) $(OBJ)

$(OBJ): $(PPINFER)

gen-anti:
	cogent $(SRC) -g -o$(OUTPUT) \
		--root-dir="$(REPO)" \
		--Wno-warn --infer-c-funcs="$(ACFILES)" \
		--cpp-args="\$$CPPIN -o \$$CPPOUT -P $(CFLAGS)" \
		--entry-funcs=entrypoints.cfg

gen-verif:
	cogent $(SRC) -g -o$(OUTPUT) \
		--root-dir="$(REPO)" \
		--shallow-normal \
		--entry-funcs=entrypoints.cfg

clean:
	rm -f $(COUTPUT) $(HOUTPUT) $(PP) $(PPINFER) $(OBJ)
	@# rm -f *-gen.*
	rm -f $(NAME)
	rm -f Square_*.thy
	rm -f ROOT
	rm -f BUILD_INFO
