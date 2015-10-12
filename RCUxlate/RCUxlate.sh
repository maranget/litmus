#! /bin/sh
#
# Convert LISA litmus test to auxiliary-variable form.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, you can access it online at
# http://www.gnu.org/licenses/gpl-2.0.html.
#
# Copyright (C) IBM Corporation, 2015
#
# Authors: Paul E. McKenney <paulmck@linux.vnet.ibm.com>

./stripocamlcomment |
gawk '

function proc_needs_gp_check(proc_num, gp_num) {
	if (!rcurl[proc_num])
		return 0;
	return rcugp[gp_num] != proc_num;
}

function stmt_needs_gp_check(proc_num, gp_num, stmt) {
	if (!proc_needs_gp_check(proc_num, gp_num))
		return 0;
	if (stmt = "f[lock]" || stmt = "f[unlock]")
		return 0;
	if (stmt ~ /^[frw]\[/)
		return 1;
}

function do_one_gp_check(proc_num, line_in, line_out, rcurscs, rl, rul, gp_num) {
	if (stmt_needs_gp_check(proc_num, i, lisa[proc_num ":" line_in])) {
		if (rcurscs > rl)
			print "(* preamble " gp_num " *)";
		if (rul > 0)
			print "(* postamble " gp_num " *)";
	}
}

function do_gp_checks(proc_num, line_in, line_out, rcurscs, rl, rul,  i, line) {
	line = line_out;
	for (i = 1; i <= ngp; i++)
		line = do_one_gp_check(proc_num, line_in, line, i);
}

/^[ 	]*$/ {
	next;  /* Kill blank lines. */
}

NR == 1 {
	if ($1 != "LISA") {
		print "Need LISA file!";
		exit;
	}
	print $1, $2 "-Auxiliary";
	inpreamble = 1;
	next;
}

inpreamble == 1 {
	if ($1 ~ /"/)
		print;
	if ($0 ~ /{/) {
		print;
		if ($0 != "{") {
			print "Line " NR ": Single { to begin initialization!";
			exit;
		}
		inpreamble = 0;
		ininit = 1;
	}
	next;
}

ininit == 1 {
	if ($0 ~ /}/) {
		if ($0 != "}") {
			print "Line " NR ": Single } to end initialization!";
			exit;
		}
		ininit = 0;
		incode = 1;
		line = 1;
		nproc = 0;
		ngp = 0;
	} else {
		print;
	}
	next;
}

incode == 1 && $1 ~ /^exists/ {
	incode = 0;
	inexists = 1;
	exists = $0;
	gsub(/exists */, "exists (", exists);
	next;
}

incode == 1 {
	gsub(/^[ 	]*/, "");
	gsub(/;[ 	]*$/, "");
	split($0, curline, "|");
	if (nproc == 0)
		nproc = length(curline);
	else if (nproc != length(curline)) {
		print "Line " NR ": Expected " nproc " processes!";
		exit;
	}
	for (i = 1; i <= nproc; i++) {
		gsub(/^[ 	]*/, "", curline[i]);
		gsub(/[ 	]*$/, "", curline[i]);
		if (curline[i] == "f[sync]") {
			ngp++;
			rcugp[ngp] = i;
		}
		if (curline[i] == "f[lock]") {
			if (rcunest[i] + 0 == 0)
				rcurl[i]++;
			else
				curline[i] = "(* nested " curline[i] "*)";
			rcunest[i]++;
		} else if (curline[i] == "f[unlock]") {
			if (rcunest[i] == 1)
				rcurul[i]++;
			else
				curline[i] = "(* nested " curline[i] "*)";
			rcunest[i]--;
		}
		lisa[i ":" line] = curline[i];
	}
	line++;
	next;
}

inexists == 1 {
	exists = exists " " $0;
}

END {
	print nproc + 1 ":r001=1;";
	for (i = 1; i <= ngp; i++)
		print "proph" i "=1;";
	print "}";
	print ":"exists":";
	for (i = 1; i <= nproc; i++) {
		printf "Process %d: (%dR %dU) needs checks for grace periods:", i, rcurl[i], rcurul[i];
		for (j = 1; j <= ngp; j++) {
			if (proc_needs_gp_check(i, j))
				printf " %d", j;
		}
		printf "\n";
	}
}
'
