#!/bin/sh

# shortcut for "carton install --path=$PERL_LOCAL_LIB_ROOT"
# carton_install.sh --deployment also works
carton install --path=$PERL_LOCAL_LIB_ROOT $*

# we can also set the environment variable
# export PERL_CARTON_PATH=$PERL_LOCAL_LIB_ROOT
