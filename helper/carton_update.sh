#!/bin/sh

# set the environment variable
export PERL_CARTON_PATH=$PERL_LOCAL_LIB_ROOT
carton update $*

