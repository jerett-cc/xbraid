#!/bin/sh
#BHEADER**********************************************************************
# Copyright (c) 2013,  Lawrence Livermore National Security, LLC.
# Produced at the Lawrence Livermore National Laboratory.
# This file is part of WARP.  See file COPYRIGHT for details.
#                                                                          
# WARP is free software; you can redistribute it and/or modify it under the
# terms of the GNU Lesser General Public License (as published by the Free
# Software Foundation) version 2.1 dated February 1999.                    
#
#EHEADER**********************************************************************

# scriptname holds the script name, with the .sh removed
scriptname=`basename $0 .sh`

# Echo usage information
case $1 in
   -h|-help)
      cat <<EOF

   $0 [-h|-help] 

   where: -h|-help   prints this usage information and exits

   This script runs basic memory tests of warp for a constant coefficient 2D heat 
   equation. The basic strategy is to grep the output of valgrind for any instances of 
   *warp*. The output is written to $scriptname.out, $scriptname.err and 
   $scriptname.dir. This test passes if $scriptname.err is empty.

   Example usage: ./test.sh $0 

EOF
      exit
      ;;
esac

# Determine mpi command and mpi setup for this machine
HOST=`hostname`
case $HOST in
   tux*) 
      MACHINES_FILE="hostname"
      if [ ! -f $MACHINES_FILE ] ; then
         hostname > $MACHINES_FILE
      fi
      RunString="mpirun -mca btl ^openib -machinefile $MACHINES_FILE $*"
      ;;
      *) 
         RunString="mpirun"
         ;;
esac


# Setup
echo "Compiling regression test drivers"
example_dir="../examples"
test_dir=`pwd`
output_dir=`pwd`/$scriptname.dir
rm -fr $output_dir
mkdir -p $output_dir


# compile the regression test drivers against valgrind 
cd $example_dir
make clean
make valgrind=yes
cd $test_dir

# Run the following regression tests
valgrind_opts="--log-fd=1 --leak-check=full"
TESTS=( "MPIWRAP_DEBUG=quiet $RunString -np 1 valgrind $valgrind_opts $example_dir/drive-05 -pgrid 1 1 1 -nt 64 -ml 15 " \
        "MPIWRAP_DEBUG=quiet $RunString -np 2 valgrind $valgrind_opts $example_dir/drive-05 -pgrid 1 1 2 -nt 64 -cf 4 -ml 15 -fmg " \
        "MPIWRAP_DEBUG=quiet $RunString -np 2 valgrind $valgrind_opts $example_dir/drive-05 -pgrid 1 1 2 -nt 64 -cf 4 -ml 15 -fmg -write_level 1" \
        "MPIWRAP_DEBUG=quiet $RunString -np 4 valgrind $valgrind_opts $example_dir/drive-05 -pgrid 1 1 4 -nt 32 -cf 4 -ml 15 -fmg " )

# The below commands will then dump each of the tests to the output files 
#   $output_dir/unfiltered.std.out.0, 
#   $output_dir/std.out.0, 
#   $output_dir/std.err.0,
#    
#   $output_dir/unfiltered.std.out.1,
#   $output_dir/std.out.1, 
#   $output_dir/std.err.1,
#   ...
#
# The unfiltered output is the direct output of the script, whereas std.out.*
# is filtered by a grep for the lines that are to be checked.  
#
lines_to_check=" _warp.* | warp.* |^  time steps.*|^  number of levels.*|^  coarsening factor.*|^  num F-C relaxations.*|^  num rels on level 0.*|^  iterations.*|^spatial problem size.*"
#
# Then, each std.out.num is compared against stored correct output in 
# $scriptname.saved.num, which is generated by splitting $scriptname.saved
#
TestDelimiter='# Begin Test'
csplit -n 1 --silent --prefix $output_dir/$scriptname.saved. $scriptname.saved "%$TestDelimiter%" "/$TestDelimiter.*/" {*}
#
# The result of that diff is appended to std.err.num. 

# Run regression tests
counter=0
for test in "${TESTS[@]}"
do
   echo "Running Test $counter"
   eval "$test" 1>> $output_dir/unfiltered.std.out.$counter  2>> $output_dir/std.err.$counter
   cd $output_dir
   egrep -o "$lines_to_check" unfiltered.std.out.$counter > std.out.$counter
   diff -U3 -B -bI"$TestDelimiter" $scriptname.saved.$counter std.out.$counter >> std.err.$counter
   cd $test_dir
   counter=$(( $counter + 1 ))
done 

# Echo to stderr all nonempty error files in $output_dir.  test.sh
# collects these file names and puts them in the error report
for errfile in $( find $output_dir ! -size 0 -name "*.err.*" )
do
   echo $errfile >&2
done


# remove machinefile, if created
if [ -n $MACHINES_FILE ] ; then
   rm $MACHINES_FILE
fi
