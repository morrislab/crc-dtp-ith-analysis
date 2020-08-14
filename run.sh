#!/bin/sh
set -euo pipefail

PYTHON=$HOME/.apps/miniconda3/bin/python3
PAIRTREEDIR=~/work/pairtree
BASEDIR=~/work/sumi

PHI_FITTER=rprop
JOBDIR=~/jobs

PARALLEL=40
NCHAINS=40

function para {
  parallel -j$PARALLEL --halt 1 --eta
}

function cluster_vars {
  #for clustmodel in pairwise linfreq; do
  for clustmodel in pairwise; do
    #for prior in 0.15 0.20 0.25; do
    for prior in 0.15; do
      #for conc in $(seq -10 3); do
      for conc in -3; do
        outd=$CLUSTRESULTSDIR/clusters.${clustmodel}.conc$(echo $conc | tr - _).prior$(echo $prior | sed 's/\.//')
        #[[ $prior == 0.15 && $clustmodel == pairwise && $conc == -3 ]] && continue
        mkdir -p $outd

        for foo in $INDIR/*.ssm; do
          runid=$(basename $foo | cut -d. -f1)
          jobfn=$(mktemp)

          cmd=""
          cmd+="#!/bin/bash\n"
          cmd+="#SBATCH --nodes=1\n"
          cmd+="#SBATCH --ntasks=$PARALLEL\n"
          cmd+="#SBATCH --time=23:59:00\n"
          cmd+="#SBATCH --job-name sumi_clust_$runid\n"
          cmd+="#SBATCH --output=$JOBDIR/slurm_clust_${runid}_%j.txt\n"
          cmd+="#SBATCH --mail-type=NONE\n"

          cmd+="$PYTHON $PAIRTREEDIR/bin/clustervars"
          cmd+=" --model $clustmodel"
          cmd+=" --parallel $PARALLEL"
          cmd+=" --chains $NCHAINS"
          cmd+=" --iterations 10000"
          cmd+=" --concentration $conc"
          cmd+=" --prior $prior"
          cmd+=" --seed 1337"
          cmd+=" --full-results $outd/$runid.clusterings.npz"
          cmd+=" $INDIR/$runid.{ssm,params.json}"
          cmd+=" $outd/$runid.params.json"
          cmd+=" 2>$outd/$runid.stderr"

          echo -e $cmd > $jobfn
          sbatch $jobfn
          rm $jobfn
        done
      done
    done
  done #| parallel -j3 --halt 2 --eta
}

function make_cluster_llh_cmd {
  logconc=$1
  prior=$2
  model=$3
  ssmfn=$4
  resultfn=$5

  cmd="\$($PYTHON $PAIRTREEDIR/comparison/pairtree/calc_cluster_llh.py --parallel 0 --concentration $logconc --prior $prior --model $model $ssmfn $resultfn | awk '{print \$2}')"
  echo $cmd
}

function compare_cluster_stats {
  cd $CLUSTRESULTSDIR
  for handbuiltfn in clusters.handbuilt/*.params.json; do
    runid=$(basename $handbuiltfn | cut -d. -f1)
    (
      echo "run,C_hb,C_soln,homo,comp,vm,ami,nlglh_hb,nlglh_soln"

      for resultfn in clusters.*/${runid}.params.json; do
        params=$(dirname $resultfn | cut -d. -f2-)
        if [[ $params != handbuilt ]]; then
          model=$(echo $params | cut -d. -f1)
          logconc=$(echo $params | cut -d. -f2 | cut -c5- | tr _ -)
          prior=0.$(echo $params | cut -d. -f3 | cut -c7-)
          ssmfn=$INDIR/$runid.ssm
          hb_cmd=$(make_cluster_llh_cmd $logconc $prior $model $ssmfn $handbuiltfn)
          soln_cmd=$(make_cluster_llh_cmd $logconc $prior $model $ssmfn $resultfn)
        else
          hb_cmd="\$(echo -1)"
          soln_cmd=$hb_cmd
        fi

        echo echo "$params,\$($PYTHON $BASEDIR/bin/compute_cluster_stats.py clusters.handbuilt/$runid.params.json $resultfn),$hb_cmd,$soln_cmd"
      done #| parallel | sort -nk6 -t,
    ) > stats.$runid.csv
  done
}

function plot_clusters {
  for foo in $CLUSTRESULTSDIR/clusters.*/*.params.json; do
    runid=$(basename $foo | cut -d. -f1)
    echo "$PYTHON $PAIRTREEDIR/bin/plotvars --parallel 1 $INDIR/$runid.ssm $foo $(dirname $foo)/$runid.clusters.html 2>&1"
  # `true` because we need noop so Bash doesn't terminate when grep matches nothing.
  done | parallel -j40 --halt 1 --eta | grep -v '^{' || true
}

function make_cluster_index {
  cd $CLUSTRESULTSDIR

  for foo in stats.*.csv; do
    runid=$(echo $foo | cut -d. -f2)
    echo "<h2>$runid</h2>"
    $PYTHON $BASEDIR/bin/csv2html.py <(head -n1 $foo; cat $foo | tail -n+2 | sed -r 's|([^,]+)|<a href=clusters.\1/'$runid'.clusters.html>\1</a>|')
  done > index.html
}

function run_pairtree {
  for infn in $INDIR/*.ssm; do
    runid=$(basename $infn | cut -d. -f1)
    resultdir=$TREERESULTSDIR/$runid

    [[ -f $INDIR/${runid}.params.json ]] || continue

    cmd=""
    cmd+="mkdir -p $resultdir"
    cmd+=" && $PYTHON $PAIRTREEDIR/bin/pairtree"
    cmd+=" --params $INDIR/${runid}.params.json"
    cmd+=" --trees-per-chain 3000"
    cmd+=" --tree-chains 40"
    cmd+=" --parallel 40"
    cmd+=" --seed 1337"
    cmd+=" --phi-fitter $PHI_FITTER"
    cmd+=" $INDIR/${runid}.ssm"
    cmd+=" $resultdir/${runid}.results.npz"
    cmd+=" > $resultdir/${runid}.stdout"
    cmd+=" 2> $resultdir/${runid}.stderr"
    echo $cmd
  done
}

function plot_results {
  #for resultsfn in $TREERESULTSDIR/*/*.results.npz; do
  #  runid=$(basename $resultsfn | cut -d. -f1)
  #  outdir=$(dirname $resultsfn)

  #  cmd="$PYTHON $BASEDIR/bin/colour_pops.py"
  #  cmd+=" $runid"
  #  cmd+=" $INDIR/${runid}.params.json"
  #  cmd+=" $resultsfn"
  #  cmd+=" $outdir/$runid.params.json"
  #  cmd+=" >$outdir/$runid.colour_map.html"
  #  echo $cmd
  #done | para

  for resultsfn in $TREERESULTSDIR/*/*.results.npz; do
    runid=$(basename $resultsfn | cut -d. -f1)
    for task in plottree summposterior; do
      outdir=$(dirname $resultsfn)

      cmd=""
      cmd+=" $PYTHON $PAIRTREEDIR/bin/$task"
      if [[ $task == plottree ]]; then
        cmd+=" --phi-orientation samples_as_rows"
        cmd+=" --reorder-subclones"
        cmd+=" --remove-normal"
        cmd+=" --seed 43"
      fi
      cmd+=" --runid $runid"
      cmd+=" $INDIR/${runid}.ssm"
      cmd+=" $INDIR/${runid}.params.json"
      cmd+=" $outdir/${runid}.results.npz"
      cmd+=" $outdir/${runid}.$task.html"
      echo $cmd
    done
  done | para
}

function add_colour_map {
  for resultsfn in $TREERESULTSDIR/*/*.plottree.html; do
    runid=$(basename $resultsfn | cut -d. -f1)
    outdir=$(dirname $resultsfn)
    outfn=$(mktemp)
    (
      cat $outdir/$runid.colour_map.html
      cat $resultsfn
    ) > $outfn
    mv $outfn $resultsfn
  done
}

function add_diversity {
  for outfn in $TREERESULTSDIR/*/*.plottree.html; do
    runid=$(basename $outfn | cut -d. -f1)
    # This only works for POP66, where we have treatment-resistant and non-TR samples.
    [[ $runid == POP66 ]] || continue

    resultfn=$(dirname $outfn)/${runid}.results.npz
    ssmfn=$INDIR/$runid.ssm
    tmpfn=$(mktemp)

    cmd="$PYTHON $BASEDIR/bin/compare_diversity.py"
    cmd+=" --print-html"
    cmd+=" $ssmfn"
    cmd+=" $resultfn"

    (
      $cmd
      cat $outfn
    ) > $tmpfn
    mv $tmpfn $outfn
  done
}

function plot_entropy {
  for resultsfn in $TREERESULTSDIR/*/*.results.npz; do
    outd=$(dirname $resultsfn)
    runid=$(basename $resultsfn | cut -d. -f1)
    cmd="$PYTHON $BASEDIR/bin/plot_entropy.py "
    cmd+=" $resultsfn"
    cmd+=" $outd/$runid.entropy.{csv,html}"
    echo $cmd
  done
}

function append_entropies {
  for entfn in $TREERESULTSDIR/*/*.entropy.html; do
    runid=$(basename $entfn | cut -d. -f1)
    plotfn=$(dirname $entfn)/$runid.plottree.html
    outfn=$(mktemp)

    (
      cat $plotfn | head -n-1
      cat $entfn
      cat $plotfn | tail -n1
    ) > $outfn
    mv $outfn $plotfn
  done
}

function main {
  cluster_vars
  #compare_cluster_stats
  #plot_clusters
  #make_cluster_index

  #run_pairtree | para

  #plot_results
  #add_colour_map
  #add_diversity

  #plot_entropy | para
  #append_entropies
}

#for suffix in nocna withcna; do
#for suffix in nocna.{separated,zerocounts}; do
for suffix in nocna.separated; do
#for suffix in nocna.combined; do
  INDIR=$BASEDIR/inputs.$suffix
  CLUSTRESULTSDIR=$BASEDIR/scratch/clusters.$suffix
  TREERESULTSDIR=$BASEDIR/scratch/trees.omega05.${PHI_FITTER}.$suffix
  main
done
