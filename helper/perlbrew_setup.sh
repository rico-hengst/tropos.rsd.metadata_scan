#!/bin/bash
#  Usage
#  perlbrew_setup.sh <install_path>
#
#  script only works with the shebang above!?
#
#  perlbrew_setup.sh
#
#  A quick&dirty script to init perlbrew-environement
#
#  It will init perlbrew inside running users home and will add
#  some config to user's bashrc.

# speed up perlbrew install!?
export TEST_JOBS=9;

# Setting default values
# 1st: command parameter, 2nd: PERLBREW_ROOT from ENV, 3rd: ~/perl5/perlbrew
PERLBREW_ROOT_PATH=${1:-$PERLBREW_ROOT};
PERLBREW_ROOT_PATH=${PERLBREW_ROOT_PATH:-~/perl5/perlbrew};

# setting path to ENV
export PERLBREW_ROOT=$PERLBREW_ROOT_PATH;

type curl || exit 1; #  abort, if curl isn't available

curl -L http://install.perlbrew.pl | bash;

#  init not needed by installation with curl!?
#  perlbrew init
echo source $PERLBREW_ROOT/etc/bashrc >> ~/.bashrc;
source $PERLBREW_ROOT/etc/bashrc;
perlbrew install perl-5.22.2;
perlbrew lib create perl-5.22.2@devel;
perlbrew switch perl-5.22.2@devel;
perlbrew install-cpanm;
cpanm Carton;
echo
echo "Starting a new shell, perlbrew should be up and fully functional from there!";
echo
#exec bash;
