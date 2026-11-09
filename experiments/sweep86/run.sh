#!/bin/sh
# Item 86 sweep: one variant_horizon run per (family, KCTRIAL). Usage: sh sweep86/run.sh FAMILY KCTRIAL [SEEDS]
cd "$(dirname "$0")/.."
FAM=$1; K=$2; SD=${3:-1,2,3,4,5,6,7,8,9,10}; TAG=$FAM-$K-$(echo $SD | tr ',' '_' | cut -c1-12)
case $FAM in
  G)  ENVS="GROW=1 SEDFADE=1" ;;
  S)  ENVS="" ;;
  SF) ENVS="SEDFADE=1" ;;
esac
env $ENVS KCTRIAL=$K HORIZONS=294,392,588 SEEDS=$SD OUT=$PWD/sweep86/$TAG.json julia --project=.. variant_horizon.jl > sweep86/$TAG.out 2>&1
echo "done $TAG"
