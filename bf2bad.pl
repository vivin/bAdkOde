#
# Brainfuck to bAdkOde translator
# Copyright Vivin Suresh Paliath(2009)
# Licensed under GPLv3
#

#!/usr/bin/perl

 use strict;

 my $terminator = $/;
 undef $/;
 my $bf = <STDIN>;
 $bf =~ s/[^<>\[\]\.,\+\-\s\n]//g;
 $/ = $terminator;

 my $i = 0;

 print ">0a";

 while($i < length($bf)) {
    
    my $bf_instruction = substr($bf, $i, 1);
   
    if($bf_instruction eq '>') {
       print "+1a";
    }

    elsif($bf_instruction eq '<') {
       print "-1a";
    }

    elsif($bf_instruction eq '+') {
       print "+1[a";
    }

    elsif($bf_instruction eq '-') {
       print "-1[a";
    }

    elsif($bf_instruction eq '.') {
       print "\"[a";
    }

    elsif($bf_instruction eq ',') {
       print "?[a";
    }

    elsif($bf_instruction eq '[') {
       print "{![a";
    }

    elsif($bf_instruction eq ']') {
       print "}";
    }

    else {
       print $bf_instruction;
    }   

    $i++;
 }
 
