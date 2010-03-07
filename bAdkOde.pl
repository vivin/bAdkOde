#
# bAdkOde.pl
#
# Copyright Vivin Suresh Paliath (2005).
# The sourcecode is licensed under GLPv3
#

#!/usr/bin/perl

 use strict;
 use Getopt::Mixed;
 use Term::ReadKey;
 use Data::Dumper;

 my %macros;
 my %labels;
 my @badkode_arr;
 my $filename;
 my $include;
 my $badkode_line;
 my $include_line;
 my $badkode_idx = 0;
 my $org_badkode_idx = 0;
 my $a = 0;
 my $b = 0;
 my @stack;
 my $stk_idx = 0;
 my @memory;
 my $mem_idx = 0;
 my $translate;
 my $coutfile;
 my $debug;
 my $debugfile;
 my $indent = 4;
 my $c = "";
 my $i;
 my $j;

 Getopt::Mixed::init('t:s
                      d=s
                      h:s
                      translate>t
                      debug>d
                      help>h'
                    );

 while(my($option, $value, $pretty) = Getopt::Mixed::nextOption())
 {
       OPTION:
       {
             $option eq 't' and do
             {
                     $translate = 1;
                     $coutfile = $value if $value;
             };

             $option eq 'd' and do
             {
                     $debug = 1;
                     $debugfile = $value if $value;
             };
 
             $option eq 'h' and do
             {
                     print "Syntax: $0 [options] filename.bad\n";
                     print "        where [options] are:\n\n";
                     print "        -t[=filename]|--translate[=filename]\tTranslate bAdkOde to C. If no filename argument is provided, translated version is printed to STDOUT.\n";
                     print "        -d=filename|--debug=filename\t\tPrint debug stuff for interpreter. You need to specify a debug file that the script can dump to.\n";
                     print "        -h|--help\t\t\t\tPrints this message.\n\n";
                     exit 1;
             };
       }
 }

 Getopt::Mixed::cleanup();

 my $filename = $ARGV[0];

 if(!$filename)
 {
    print "Syntax: $0 [options] filename.e\n";
    print "        where [options] are:\n\n";
    print "        -t[=filename]|--translate[=filename]\tTranslate bAdkOde to C. If no filename argument is provided, translated version is printed to STDOUT.\n";
    print "        -d=filename|--debug=filename\t\tPrint debug stuff for interpreter. You need to specify a debug file that the script can dump to.\n";
    print "        -h|--help\t\t\t\tPrints this message.\n\n";
    exit 1;
 }

 if($debug)
 {
    open(DEBUG, ">$debugfile");
 }

 #
 # Do preprocessing stuff - parsing includes and finding macros and stuff
 # and then expand macros and then split into tokens
 #

 $badkode_line = &expand_labels(&expand_macros(&preprocess($filename, $badkode_line), $filename), $filename);

 if($debug) {
    print DEBUG "Expanded code: $badkode_line\n\n";
 }

 @badkode_arr = $badkode_line =~ /({|}|\(|\)|>|-|\+|=|'|"|\?|!|\d+|\[*[ab])/g;

 if(!$translate)
 {
    ReadMode 'cbreak';

    if(!&interpret(\@badkode_arr, $badkode_idx, \@memory, \@stack, 0))
    {
       ReadMode 'normal';
       print "Script $filename terminated with an error.";
    }

    if($debug) {
       my $mem = Data::Dumper->new([\@memory], ["memory"]);
       my $stk = Data::Dumper->new([\@stack], ["stack"]);
       print DEBUG $mem->Dump;
       print DEBUG $stk->Dump;
    }

    ReadMode 'normal';
 }

 else
 {
    $c = "#include <stdio.h>\n\n";

    $c .= "int main()\n";
    $c .= "{\n";
    $c .= ' ' x $indent . "long int a = 0;\n";
    $c .= ' ' x $indent . "long int b = 0;\n\n";

    $c .= ' ' x $indent . "long int mem[131072];\n\n";
    $c .= ' ' x $indent . "long int stack[131072];\n\n";

    $c .= ' ' x $indent . "long int top = 0;\n";
    $c .= ' ' x $indent . "long int i = 0;\n\n";

    $c .= ' ' x $indent . "for(i = 0; i < 131072; i++)\n";
    $c .= ' ' x $indent . "{\n";
    $c .= ' ' x $indent . "    mem[i] = 0;\n";
    $c .= ' ' x $indent . "    stack[i] = 0;\n";
    $c .= ' ' x $indent . "}\n\n";
    
    if(!&translate(\@badkode_arr, $badkode_idx))
    {
       print "Script $filename terminated with an error.";
    }

    $c .= ' ' x $indent . "return 0;\n";
    $c .= "}\n";

    $c =~ s/([ab]) -= 1;/\1--;/g;
    $c =~ s/([ab]) \+= 1;/\1++;/g;
    $c =~ s/mem\[([ab])\] -= 1;/mem[\1]--;/g;
    $c =~ s/mem\[([ab])\] \+= 1;/mem[\1]++;/g;

    if($coutfile)
    {
       open(C, ">$coutfile");
       print C $c;
       close(C);
    }

    else
    {
       print $c;
    }
 }

 if($debug)
 {
    close(DEBUG);
 }

 #
 # ---------------
 # Subs start here
 # ---------------
 #

 sub preprocess
 {
     my $local_filename = $_[0];
     my $local_badkode_line = $_[1];

     open(IN, "<$local_filename");

     while(<IN>)
     {
           chomp;
           $_ =~ s/^\s+//;
           $_ =~ s/\s+$//;
           $_ =~ s/#.*$//;
           $local_badkode_line .= $_;
     }

     close(IN);

     #
     # Identify includes
     #

     &id_includes($local_badkode_line, $local_filename);

     #
     # Identify labels
     #

     &id_labels($local_badkode_line, $local_filename);

     #
     # Identify macros
     #

     &id_macros($local_badkode_line, $local_filename);

     $local_badkode_line =~ s/@.*;//g;
     $local_badkode_line =~ s/\*.*;//g;
     $local_badkode_line =~ s/%.*;//g;

     return $local_badkode_line;
 }

 sub id_includes
 {
     my $local_badkode_line = $_[0];
     my $local_filename = $_[1];
     my @local_badkode_arr = split(/%/, $local_badkode_line);
     shift(@local_badkode_arr);

     foreach my $token(@local_badkode_arr)
     {
             $token =~ m/[^;]+/;
             $include = $&;
             $include =~ s/include +//;

             if(! -e $include)
             {
                print "$local_filename: Could not find $include.\n";
                exit 1;
             }

             &preprocess($include);
     }
 }

 sub id_labels
 {
     my $local_badkode_line = $_[0];
     my $local_filename = $_[1];

     my $label;
     my $value;

     my @local_badkode_arr = split(/\*/, $local_badkode_line);
     shift(@local_badkode_arr);

     foreach my $token(@local_badkode_arr)
     {
             if($token =~ m/[^=]+/)
             {
                $label = $&;
                $label =~ s/\s//g;
             }

             else 
             {
                print "$local_filename: Something's wrong with your label definition(s). Most probably you have a _ without a following label name.\n";
                exit 1;
             }

             if($token =~ m/\s*=\s*[^;]+/)
             {
                $value = $&;
                $value =~ s/\s*=\s*//;
                $value =~ s/\s//g;
             }

             if($labels{$label})
             {
                print "$local_filename: $label has already been defined in " . $labels{$label}->{file} . ".\n";
                exit 1;
             }

             $labels{$label}->{value} = $value;
             $labels{$label}->{file} = $local_filename;
     }
 }

 sub id_macros
 {
     my $local_badkode_line = $_[0];
     my $local_filename = $_[1];

     my $macro;
     my $body;
     my $params;

     my @local_badkode_arr = split(/@/, $local_badkode_line);
     shift(@local_badkode_arr);
 
     foreach my $token(@local_badkode_arr)
     {
             if($token =~ m/[^\(]+/)
             {
                $macro = $&;
                $macro =~ s/\s//g;
             }

             else
             {
                print "$local_filename: Something's wrong with your macro definition(s). Most probably you have an @ without a following macro name.\n";
                exit 1;
             }

             if($token =~ m/\(.*\)\s*=\s*/)
             {
                $params = $&;
                $params =~ s/\s*=\s*//;
                $params =~ s/\s//g;
                $params =~ s/[\(\)]//g;
             }

             else
             {
                print "$local_filename: I can't find a parameter list for the $macro macro.\n";
                exit 1;
             }

             if($token =~ m/\s*=\s*.*;/)
             {
                $body = $&;
                $body =~ s/\s*=\s*//;
                $body =~ s/\s//g;
                $body =~ s/;//;
             }

             else
             {
                print "$local_filename: I can't find a body for the $macro macro. You might be missing a semicolon.\n";
                exit 1;
             }

             $macro .= "/" . scalar split(/,/, $params);

             if($macros{$macro})
             {
                print "$local_filename: $macro has already been defined in " . $macros{$macro}->{file} . ".\n";
                exit 1;
             }

             $macros{$macro}->{params} = $params;
             $macros{$macro}->{body} = $body;
             $macros{$macro}->{file} = $local_filename;
     }
 }

 sub expand_labels
 {
     my $local_badkode_line = $_[0];
     my $local_filename = $_[1];
     my @local_badkode_arr;

     my $label;
     my $pattern;
     my $replacement;

     my $i;

     my $token;

     while($local_badkode_line =~ /\$/)
     {
           @local_badkode_arr = $local_badkode_line =~ /({|}|\(|\)|>|-|\+|=|'|"|\?|!|\$[a-zA-Z0-9_]+\$|&[a-zA-Z0-9_]+\([^)]*\)|\d+|\[*[ab])/g;
           $local_badkode_line = "";

           for($i = 0; $i < scalar @local_badkode_arr; $i++)
           {
               $token = $local_badkode_arr[$i];

               if($token !~ /\$/)
               {
                  $local_badkode_line .=  $token;
               }
 
               else
               {
                  $label = $token;
                  $label =~ s/\$//g;

                  if(!$labels{$label})
                  {
                     print "$local_filename: Label $label has not been defined.\n";
                     exit 1;
                  }
 
                  $local_badkode_line .= $labels{$label}->{value};
               }
           }
     }

     return $local_badkode_line;
 }

 sub expand_macros
 {
     my $local_badkode_line = $_[0];
     my $local_filename = $_[1];
     my @local_badkode_arr;

     my $macro;
     my $body;

     my $pattern;
     my $replacement;
     my $exp_body;

     my @def_params_arr;
     my $def_params;

     my @params_arr;
     my $params;

     my $i;
     my $j;

     my $token;

     while($local_badkode_line =~ /&/)
     {
           @local_badkode_arr = $local_badkode_line =~ /({|}|\(|\)|>|-|\+|=|'|"|\?|!|\$[a-zA-Z0-9_]+\$|&[a-zA-Z0-9_]+\([^)]*\)|\d+|\[*[ab])/g;
           $local_badkode_line = "";

           for($i = 0; $i < scalar @local_badkode_arr; $i++)
           {
               $token = $local_badkode_arr[$i];
 
               if($token !~ "&")
               {
                  $local_badkode_line .=  $token;
               }
 
               else
               {
                  $token =~ m/[^\(]+/;
                  $macro = $&;
                  $macro =~ s/&//;
 
                  $token =~ m/\([^\)]*\)/;
                  $params = $&;
                  chop($params);
                  $params =~ s/\s//g;
                  $params =~ s/[\(\)]//g;
                  @params_arr = split(/,/, $params);
 
                  $macro .= "/" . scalar @params_arr;
 
                  if(!$macros{$macro})
                  {
                     print "$local_filename: Macro $macro has not been defined.\n";
                     exit 1;
                  }
 
                  $def_params = $macros{$macro}->{params};
                  @def_params_arr = split(/,/, $def_params);
 
                  $exp_body = $macros{$macro}->{body};
 
                  if(scalar @params_arr != scalar @def_params_arr)
                  {
                     print "$local_filename: Number of parameters in definition and call don't match for macro $macro\n";
                  }
 
                  for($j = 0; $j < scalar @params_arr; $j++)
                  {
                      $pattern = $def_params_arr[$j];
                      $replacement = $params_arr[$j];
                      $exp_body =~ s/$pattern/$replacement/g;
                  }
 
                  $local_badkode_line .= $exp_body;
               }
           }
      }

      return $local_badkode_line;
 }


 sub interpret
 {
     my $badkode_arr_ref = $_[0];
     my $badkode_idx = $_[1];
     my $mem_ref = $_[2];
     my $stk_ref = $_[3];
     my $rec_lev = $_[4];
     my $indent = '  ' x $rec_lev;
     my $braces = 0;
     my $junk;

     do
     {
          my $param1 = $badkode_arr_ref->[$badkode_idx + 1];
          my $ptype1 = &typeof($param1);
          my $param2 = $badkode_arr_ref->[$badkode_idx + 2];
          my $ptype2 = &typeof($param2);
          my $param3 = $badkode_arr_ref->[$badkode_idx + 3];
          my $ptype3 = &typeof($param3); 

          $braces = 0;

          CASE:
          {
               ($badkode_arr_ref->[$badkode_idx] eq '>') && do
               {
                                         if($debug)
                                         {
                                            print DEBUG $indent . "Token $badkode_idx is >: move\n";
                                         }

                                         $param1 = &evaluate($param1, $mem_ref);

                                         if($param1 eq '' || $ptype2 eq '')
                                         {
                                            print "Bad parameter after > (token " . ($badkode_idx + 1) . ").\n $param1 and $param2 and $param3\n";
                                            return 0;
                                         }

                                         if($ptype2 eq "reg")
                                         {
                                            eval("\$$param2 = $param1");
                                         }

                                         elsif($ptype2 eq "mem")
                                         {
                                               $param2 =~ s/\[//;
                                               eval("\$mem_ref->[\$$param2] = $param1");
                                         }

                                         else
                                         {
                                            print "Destination parameter for > cannot be a number (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         $badkode_idx += 2;

               };

               ($badkode_arr_ref->[$badkode_idx] eq '+') && do
               {
                                         if($debug)
                                         {
                                            print DEBUG $indent . "Token $badkode_idx is +: add\n";
                                         }

                                         $param1 = &evaluate($param1, $mem_ref); 

                                         if($param1 eq '' || $ptype2 eq '')
                                         {
                                            print "Bad parameter after + (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         if($ptype2 eq "reg")
                                         {
                                            eval("\$$param2 += $param1");
                                         }

                                         elsif($ptype2 eq "mem")
                                         {
                                               $param2 =~ s/\[//;
                                               eval("\$mem_ref->[\$$param2] += $param1");
                                         }

                                         else
                                         {
                                            print "Destination parameter for + cannot be a number (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }
   
                                         $badkode_idx += 2;

               };
 
               ($badkode_arr_ref->[$badkode_idx] eq '-') && do
               {
                                         if($debug)
                                         {
                                            print DEBUG $indent . "Token $badkode_idx is -: subtract\n";
                                         }

                                         $param1 = &evaluate($param1, $mem_ref);

                                         if($param1 eq '' || $ptype2 eq '')
                                         {
                                            print "Bad parameter after - (token " . ($badkode_idx + 1) . ").\n $param1 and $param2 and $param3\n";
                                            return 0;
                                         }

                                         if($ptype2 eq "reg")
                                         {
                                            eval("\$$param2 = \$$param2 - $param1");
                                         }

                                         elsif($ptype2 eq "mem")
                                         {
                                               $param2 =~ s/\[//;
                                               eval("\$mem_ref->[\$$param2] = \$mem_ref->[\$$param2] - $param1");
                                         }

                                         else
                                         {
                                            print "Destination parameter for - cannot be a number (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }
 
                                         $badkode_idx += 2;

               };

               ($badkode_arr_ref->[$badkode_idx] eq ')') && do
               {
                                         if($debug)
                                         {
                                            print DEBUG $indent . "Token $badkode_idx is ): push\n";
                                         }

                                         $param1 = &evaluate($param1, $mem_ref);

                                         if($param1 eq '')
                                         {
                                            print "Bad parameter after ) (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }
                                         
                                         push(@{$stk_ref}, $param1);

                                         $badkode_idx += 1;
               };

               ($badkode_arr_ref->[$badkode_idx] eq '(') && do
               {
                                         if($debug)
                                         {
                                            print DEBUG $indent . "Token $badkode_idx is (: pull\n";
                                         }

                                         if($ptype1 eq "num")
                                         {
                                            print "Destination parameter for ( cannot be a number (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         elsif($ptype1 eq '')
                                         {
                                               print "Bad parameter after ( (token " . ($badkode_idx + 1) . ").\n";
                                               return 0;
                                         }

                                         elsif($ptype1 eq "reg")
                                         {
                                               if(scalar @{$stk_ref} == 0)
                                               {
                                                  print "Stack underflow (token " . ($badkode_idx + 1) . ").\n";
                                                  return 0;
                                               }

                                               eval("\$$param1 = pop(\@{\$stk_ref})");
                                         }

                                         else
                                         {
                                               if(scalar @{$stk_ref} == 0)
                                               {
                                                  print "Stack underflow (token " . ($badkode_idx + 1) . ").\n";
                                                  return 0;
                                               }

                                               $param1 =~ s/\[//;
                                               eval("\$mem_ref->[\$$param1] = pop(\@{\$stk_ref})");
                                         }
                                         
                                         $badkode_idx += 1;
               };

               ($badkode_arr_ref->[$badkode_idx] eq '\'') && do
               {
                                         if($debug)
                                         {
                                            print DEBUG $indent . "Token $badkode_idx is ': print value\n";
                                         }

                                         if($ptype1 eq '')
                                         {
                                            print "Bad parameter after ' (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         elsif($ptype1 eq "num")
                                         {
                                               print $param1;
                                               #system("echo -n $param1");
                                         }

                                         elsif($ptype1 eq "reg")
                                         {
                                               eval("print \$$param1");
                                               #eval("system(\"echo -n \$$param1\")");
                                         }

                                         else
                                         {
                                               $param1 =~ s/\[//;
                                               eval("print \$mem_ref->[\$$param1]");
                                               #eval("system(\"echo -n \$mem_ref->[\$$param1]\")");
                                         }
                                         
                                         $badkode_idx += 1;
               };

               ($badkode_arr_ref->[$badkode_idx] eq '"') && do
               {
                                         if($debug)
                                         {
                                            print DEBUG $indent . "Token $badkode_idx is \": print chr(value)\n";
                                         }
 
                                         if($ptype1 eq '')
                                         {
                                            print "Bad parameter after \" (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         elsif($ptype1 eq "num")
                                         {
                                               print chr($param1);
                                               #system("echo -n " . chr($param1));
                                         }

                                         elsif($ptype1 eq "reg")
                                         {
                                               eval("print chr(\$$param1)");
                                               #eval("system(\"echo -n \" . chr(\$$param1))");
                                         }

                                         else
                                         {
                                               $param1 =~ s/\[//;
                                               eval("print chr(\$mem_ref->[\$$param1])");
                                               #eval("system(\"echo -n \" . chr(\$mem_ref->[\$$param1]))");
                                         }
                                         
                                         $badkode_idx += 1;
               };
 
               ($badkode_arr_ref->[$badkode_idx] eq '?') && do
               {
                                         if($debug)
                                         {
                                            print DEBUG $indent . "Token $badkode_idx is ?: input\n";
                                         }

                                         if($ptype1 eq "num")
                                         {
                                            print "Destination parameter for ? cannot be a number (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         elsif($ptype1 eq '')
                                         {
                                               print "Bad parameter after ? (token " . ($badkode_idx + 1) . ").\n";
                                               return 0;
                                         }

                                         elsif($ptype1 eq "reg")
                                         {
                                               eval("\$$param1 = ord(ReadKey(0))");
                                               eval("print chr(\$$param1)");
                                         }

                                         else
                                         {
                                               $param1 =~ s/\[//;

                                               eval("\$mem_ref->[\$$param1] = ord(ReadKey(0))");
                                               eval("print chr(\$mem_ref->[\$$param1])");
                                         }
                                         
                                         $badkode_idx += 1;
               };

               ($badkode_arr_ref->[$badkode_idx] eq '}') && do
               {
                                         if($debug)
                                         {
                                            print DEBUG $indent . "Token $badkode_idx is }: end loop\n";
                                         }

                                         return 1;# we are at the end of the loop so return 1 to previous level of recursion
               };
 
               ($badkode_arr_ref->[$badkode_idx] eq '{') && do
               {
                                         $braces = 1;

                                         if($ptype1 eq "num")
                                         {
                                            print "{ does not accept a number as a parameter (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         elsif($param1 ne "!" && $param1 ne "+" && $param1 ne "-" && $param1 ne "=")
                                         {
                                               print "Bad comparison operator after { (token " . ($badkode_idx + 1) . ").\n";
                                               return 0;
                                         }

                                         if($debug)
                                         {
                                            print DEBUG $indent . "Token $badkode_idx is {: begin loop\n";
                                         }

                                         if($param1 eq "=")
                                         {
                                            if($debug)
                                            {
                                               print DEBUG $indent . " loop type is =\n";
                                            }

                                            if($ptype2 eq "num")
                                            {
                                               print "{ does not accept a number as a parameter (token " . ($badkode_idx + 1) . ").\n";
                                            }

                                            elsif($ptype2 eq "reg")
                                            {
                                                  eval("\$junk = \$$param2");
                                            }

                                            elsif($ptype2 eq "mem") 
                                            {
                                                  $param2 =~ s/\[//;
                                                  eval("\$junk = \$mem_ref->[\$$param2]");
                                            }

                                            else
                                            {
                                               print "Bad parameter after ! in { (token " . ($badkode_idx + 1) . ").\n";
                                               return 0;
                                            }

                                            if($junk != 0)
                                            {
                                               if($debug)
                                               {
                                                  print DEBUG $indent . "Encountered loop end condition $param2 was $junk\n";
                                               }

                                               $org_badkode_idx = $badkode_idx + 1;

                                               do
                                               { 
                                                     $junk = $badkode_arr_ref->[$badkode_idx + 1];
                                                     $braces = ($junk =~ /^{/) ? $braces + 1 : $braces;
                                                     $braces = ($junk =~ /}$/) ? $braces - 1 : $braces;
                                               }
                                               while(++$badkode_idx < scalar(@{$badkode_arr_ref}) && $braces >= 1);

                                               if($braces != 0)
                                               {
                                                  print "Could not find matching } for { (token $org_badkode_idx).\n";
                                                  return 0;
                                               }
                                            }

                                            else
                                            {
                                               if($debug)
                                               {
                                                  print DEBUG $indent . " inside loop. $param2 is $junk\n";
                                               }

                                               if(!&interpret($badkode_arr_ref, $badkode_idx + 3, $mem_ref, $stk_ref, $rec_lev + 1))
                                               {
                                                  return 0;
                                               }

                                               $badkode_idx--;
                                            }
                                         }
 
                                         elsif($param1 eq "-")
                                         {
                                            if($debug)
                                            {
                                               print DEBUG $indent . " loop type is -\n";
                                            }

                                            if($ptype2 eq "num")
                                            {
                                               print "{ does not accept a number as a parameter (token " . ($badkode_idx + 1) . ").\n";
                                            }

                                            elsif($ptype2 eq "reg")
                                            {
                                                  eval("\$junk = \$$param2");
                                            }

                                            elsif($ptype2 eq "mem") 
                                            {
                                                  $param2 =~ s/\[//;
                                                  eval("\$junk = \$mem_ref->[\$$param2]");
                                            }

                                            else
                                            {
                                               print "Bad parameter after + in { (token " . ($badkode_idx + 1) . ").\n";
                                               return 0;
                                            }

                                            if($junk >= 0)
                                            {
                                               if($debug)
                                               {
                                                  print DEBUG $indent . "Encountered loop end condition $param2 was $junk\n";
                                               }

                                               $org_badkode_idx = $badkode_idx + 1;

                                               do
                                               { 
                                                     $junk = $badkode_arr_ref->[$badkode_idx + 1];
                                                     $braces = ($junk =~ /^{/) ? $braces + 1 : $braces;
                                                     $braces = ($junk =~ /}$/) ? $braces - 1 : $braces;
                                               }
                                               while(++$badkode_idx < scalar(@{$badkode_arr_ref}) && $braces >= 1);

                                               if($braces != 0)
                                               {
                                                  print "Could not find matching } for { (token $org_badkode_idx).\n";
                                                  return 0;
                                               }
                                            }

                                            else
                                            {
                                               if($debug)
                                               {
                                                  print DEBUG $indent . " inside loop. $param2 is $junk\n";
                                               }

                                               if(!&interpret($badkode_arr_ref, $badkode_idx + 3, $mem_ref, $stk_ref, $rec_lev + 1))
                                               {
                                                  return 0;
                                               }

                                               $badkode_idx--;
                                            }
                                         }
 
                                         elsif($param1 eq "+")
                                         {
                                            if($debug)
                                            {
                                               print DEBUG $indent . " loop type is +\n";
                                            }

                                            if($ptype2 eq "num")
                                            {
                                               print "{ does not accept a number as a parameter (token " . ($badkode_idx + 1) . ").\n";
                                            }

                                            elsif($ptype2 eq "reg")
                                            {
                                                  eval("\$junk = \$$param2");
                                            }

                                            elsif($ptype2 eq "mem") 
                                            {
                                                  $param2 =~ s/\[//;
                                                  eval("\$junk = \$mem_ref->[\$$param2]");
                                            }

                                            else
                                            {
                                               print "Bad parameter after - in { (token " . ($badkode_idx + 1) . ").\n";
                                               return 0;
                                            }

                                            if($junk < 0)
                                            {
                                               if($debug)
                                               {
                                                  print DEBUG $indent . "Encountered loop end condition $param2 was $junk\n";
                                               }

                                               $org_badkode_idx = $badkode_idx + 1;

                                               do
                                               { 
                                                     $junk = $badkode_arr_ref->[$badkode_idx + 1];
                                                     $braces = ($junk =~ /^{/) ? $braces + 1 : $braces;
                                                     $braces = ($junk =~ /}$/) ? $braces - 1 : $braces;
                                               }
                                               while(++$badkode_idx < scalar(@{$badkode_arr_ref}) && $braces >= 1);

                                               if($braces != 0)
                                               {
                                                  print "Could not find matching } for { (token $org_badkode_idx).\n";
                                                  return 0;
                                               }
                                            }

                                            else
                                            {
                                               if($debug)
                                               {
                                                  print DEBUG $indent . " inside loop. $param2 is $junk\n";
                                               }

                                               if(!&interpret($badkode_arr_ref, $badkode_idx + 3, $mem_ref, $stk_ref, $rec_lev + 1))
                                               {
                                                  return 0;
                                               }

                                               $badkode_idx--;
                                            }
                                         }
 
                                         elsif($param1 eq "!")
                                         {
                                            if($debug)
                                            {
                                               print DEBUG $indent . " loop type is !\n";
                                            }

                                            if($ptype2 eq "num")
                                            {
                                               print "{ does not accept a number as a parameter (token " . ($badkode_idx + 1) . ").\n";
                                            }

                                            elsif($ptype2 eq "reg")
                                            {
                                                  eval("\$junk = \$$param2");
                                            }

                                            elsif($ptype2 eq "mem") 
                                            {
                                                  $param2 =~ s/\[//;
                                                  eval("\$junk = \$mem_ref->[\$$param2]");
                                            }

                                            else
                                            {
                                               print "Bad parameter after = in { (token " . ($badkode_idx + 1) . ").\n";
                                               return 0;
                                            }

                                            if($junk == 0)
                                            {
                                               if($debug)
                                               {
                                                  print DEBUG $indent . "Encountered loop end condition $param2 was $junk\n";
                                               }

                                               $org_badkode_idx = $badkode_idx + 1;

                                               do
                                               { 
                                                     $junk = $badkode_arr_ref->[$badkode_idx + 1];
                                                     $braces = ($junk =~ /^{/) ? $braces + 1 : $braces;
                                                     $braces = ($junk =~ /}$/) ? $braces - 1 : $braces;
                                               }
                                               while(++$badkode_idx < scalar(@{$badkode_arr_ref}) && $braces >= 1);

                                               if($braces != 0)
                                               {
                                                  print "Could not find matching } for { (token $org_badkode_idx).\n";
                                                  return 0;
                                               }
                                            }

                                            else
                                            {  
                                               if($debug)
                                               {
                                                  print DEBUG $indent . " inside loop. $param2 is $junk\n";
                                               }
 
                                               if(!&interpret($badkode_arr_ref, $badkode_idx + 3, $mem_ref, $stk_ref, $rec_lev + 1))
                                               {
                                                  return 0;
                                               }

                                               $badkode_idx--;
                                            }
                                         }
               };
          }

     }
     while(++$badkode_idx < scalar(@{$badkode_arr_ref}));

     return 1;
 }

 sub translate
 {
     my $badkode_arr_ref = $_[0];
     my $badkode_idx = $_[1];
     my $braces = 0;
     my $junk;

     do
     {
          my $param1 = $badkode_arr_ref->[$badkode_idx + 1];
          my $ptype1 = &typeof($param1);
          my $param2 = $badkode_arr_ref->[$badkode_idx + 2];
          my $ptype2 = &typeof($param2);
          my $param3 = $badkode_arr_ref->[$badkode_idx + 3];
          my $ptype3 = &typeof($param3); 

          $braces = 0;

          #print "DEBUG: operator: " . $badkode_arr_ref->[$badkode_idx] . "\n";
          #print "       param1: $param1 param2: $param2 param3: $param3\n\n";

          CASE:
          {
               ($badkode_arr_ref->[$badkode_idx] eq '>') && do
               {
                                         $param1 =~ s/\[//;
                                         $param2 =~ s/\[//;

                                         if($ptype1 ne "num" && $ptype1 ne "reg" && $ptype1 ne "mem")
                                         {
                                            print "Bad parameter after > (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         if($ptype2 ne "num" && $ptype2 ne "reg" && $ptype2 ne "mem")
                                         {
                                            print "Bad destination parameter in > (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         if($ptype2 eq "num")
                                         {
                                            print "Destination parameter for > cannot be a number (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         if($ptype1 eq "num")
                                         {
                                               if($ptype2 eq "reg")
                                               {
                                                     $c .= ' ' x $indent . "$param2 = $param1;\n\n";
                                               }

                                               elsif($ptype2 eq "mem")
                                               {
                                                     $c .= ' ' x $indent . "mem[$param2] = $param1;\n\n";
                                               }
                                         }

                                         elsif($ptype1 eq "reg")
                                         {
                                               if($ptype2 eq "reg")
                                               {
                                                     $c .= ' ' x $indent . "$param2 = $param1;\n\n";
                                               }

                                               elsif($ptype2 eq "mem")
                                               {
                                                     $c .= ' ' x $indent . "mem[$param2] = $param1;\n\n";
                                               }
                                         }

                                         elsif($ptype1 eq "mem")
                                         {
                                               if($ptype2 eq "reg")
                                               {
                                                     $c .= ' ' x $indent . "$param2 = mem[$param1];\n\n";
                                               }

                                               elsif($ptype2 eq "mem")
                                               {
                                                     $c .= ' ' x $indent . "mem[$param2] = mem[$param1];\n\n";
                                               }
                                         }

                                         $badkode_idx += 2;
               };

               ($badkode_arr_ref->[$badkode_idx] eq '+') && do
               {
                                         $param1 =~ s/\[//;
                                         $param2 =~ s/\[//;

                                         if($ptype1 ne "num" && $ptype1 ne "reg" && $ptype1 ne "mem")
                                         {
                                            print "Bad parameter after > (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         if($ptype2 ne "num" && $ptype2 ne "reg" && $ptype2 ne "mem")
                                         {
                                            print "Bad destination parameter in > (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         if($ptype2 eq "num")
                                         {
                                            print "Destination parameter for > cannot be a number (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         if($ptype1 eq "num")
                                         {
                                               if($ptype2 eq "reg")
                                               {
                                                     $c .= ' ' x $indent . "$param2 += $param1;\n\n";
                                               }

                                               elsif($ptype2 eq "mem")
                                               {
                                                     $c .= ' ' x $indent . "mem[$param2] += $param1;\n\n";
                                               }
                                         }

                                         elsif($ptype1 eq "reg")
                                         {
                                               if($ptype2 eq "reg")
                                               {
                                                     $c .= ' ' x $indent . "$param2 += $param1;\n\n";
                                               }

                                               elsif($ptype2 eq "mem")
                                               {
                                                     $c .= ' ' x $indent . "mem[$param2] += $param1;\n\n";
                                               }
                                         }

                                         elsif($ptype1 eq "mem")
                                         {
                                               if($ptype2 eq "reg")
                                               {
                                                     $c .= ' ' x $indent . "$param2 += mem[$param1];\n\n";
                                               }

                                               elsif($ptype2 eq "mem")
                                               {
                                                     $c .= ' ' x $indent . "mem[$param2] += mem[$param1];\n\n";
                                               }
                                         }

                                         $badkode_idx += 2;
               };
 
               ($badkode_arr_ref->[$badkode_idx] eq '-') && do
               {
                                         $param1 =~ s/\[//;
                                         $param2 =~ s/\[//;

                                         if($ptype1 ne "num" && $ptype1 ne "reg" && $ptype1 ne "mem")
                                         {
                                            print "Bad parameter after > (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         if($ptype2 ne "num" && $ptype2 ne "reg" && $ptype2 ne "mem")
                                         {
                                            print "Bad destination parameter in > (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         if($ptype2 eq "num")
                                         {
                                            print "Destination parameter for > cannot be a number (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         if($ptype1 eq "num")
                                         {
                                               if($ptype2 eq "reg")
                                               {
                                                     $c .= ' ' x $indent . "$param2 -= $param1;\n\n";
                                               }

                                               elsif($ptype2 eq "mem")
                                               {
                                                     $c .= ' ' x $indent . "mem[$param2] -= $param1;\n\n";
                                               }
                                         }

                                         elsif($ptype1 eq "reg")
                                         {
                                               if($ptype2 eq "reg")
                                               {
                                                     $c .= ' ' x $indent . "$param2 -= $param1;\n\n";
                                               }

                                               elsif($ptype2 eq "mem")
                                               {
                                                     $c .= ' ' x $indent . "mem[$param2] -= $param1;\n\n";
                                               }
                                         }

                                         elsif($ptype1 eq "mem")
                                         {
                                               if($ptype2 eq "reg")
                                               {
                                                     $c .= ' ' x $indent . "$param2 -= mem[$param1];\n\n";
                                               }

                                               elsif($ptype2 eq "mem")
                                               {
                                                     $c .= ' ' x $indent . "mem[$param2] -= mem[$param1];\n\n";
                                               }
                                         }

                                         $badkode_idx += 2;                                    
               };

               ($badkode_arr_ref->[$badkode_idx] eq ')') && do
               {
                                         if($ptype1 ne "num" && $ptype1 ne "reg" && $ptype1 ne "mem")
                                         {
                                            print "Bad parameter after ) (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         if($ptype1 eq "num")
                                         {
                                            $c .= ' ' x $indent . "stack[top] = $param1;\n";
                                            $c .= ' ' x $indent . "top++;\n\n";
                                         }

                                         elsif($ptype1 eq "reg")
                                         {
                                               $c .= ' ' x $indent . "stack[top] = $param1;\n";
                                               $c .= ' ' x $indent . "top++;\n\n";
                                         }

                                         elsif($ptype1 eq "mem")
                                         {
                                               $param1 =~ s/\[//;
                                               $c .= ' ' x $indent . "stack[top] = mem[$param1];\n";
                                               $c .= ' ' x $indent . "top++;\n\n";
                                         }
                                         
                                         $badkode_idx += 1;
               };

               ($badkode_arr_ref->[$badkode_idx] eq '(') && do
               {
                                         if($ptype1 ne "num" && $ptype1 ne "reg" && $ptype1 ne "mem")
                                         {
                                            print "Bad parameter after ) (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         if($ptype1 eq "num")
                                         {
                                            print "Destination parameter for ( cannot be a number (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         elsif($ptype1 eq "reg")
                                         {
                                               $c .= ' ' x $indent . "top--;\n";
                                               $c .= ' ' x $indent . "$param1 = stack[top];\n\n";
                                         }

                                         elsif($ptype1 eq "mem")
                                         {
                                               $param1 =~ s/\[//;
                                               $c .= ' ' x $indent . "top--;\n";
                                               $c .= ' ' x $indent . "mem[$param1] = stack[top];\n\n";
                                         }
                                         
                                         $badkode_idx += 1;
               };

               ($badkode_arr_ref->[$badkode_idx] eq '\'') && do
               {
                                         if($ptype1 ne "num" && $ptype1 ne "reg" && $ptype1 ne "mem")
                                         {
                                            print "Bad parameter after ' (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         if($ptype1 eq "num")
                                         {
                                            $c .= ' ' x $indent . "printf(\"$param1\");\n\n";
                                            return 0;
                                         }

                                         elsif($ptype1 eq "reg")
                                         {
                                               $c .= ' ' x $indent . "printf(\"\%d\", $param1);\n\n";
                                         }

                                         elsif($ptype1 eq "mem")
                                         {
                                               $param1 =~ s/\[//;
                                               $c .= ' ' x $indent . "printf(\"\%d\", mem[$param1]);\n\n";
                                         }
                                         
                                         $badkode_idx += 1;
               };

               ($badkode_arr_ref->[$badkode_idx] eq '"') && do
               {
                                         if($ptype1 ne "num" && $ptype1 ne "reg" && $ptype1 ne "mem")
                                         {
                                            print "Bad parameter after \" (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         if($ptype1 eq "num")
                                         {
                                            $c .= ' ' x $indent . "putchar($param1);\n\n";
                                         }

                                         elsif($ptype1 eq "reg")
                                         {
                                               $c .= ' ' x $indent . "putchar($param1);\n\n";
                                         }

                                         elsif($ptype1 eq "mem")
                                         {
                                               $param1 =~ s/\[//;
                                               $c .= ' ' x $indent . "putchar(mem[$param1]);\n\n";
                                         }
                                         
                                         $badkode_idx += 1;
               };
 
               ($badkode_arr_ref->[$badkode_idx] eq '?') && do
               {
                                         if($ptype1 ne "num" && $ptype1 ne "reg" && $ptype1 ne "mem")
                                         {
                                            print "Bad parameter after \" (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         if($ptype1 eq "num")
                                         {
                                            print "Destination parameter for ? cannot be a number (token " . ($badkode_idx + 1) . ").\n";
                                            return 0;
                                         }

                                         if($ptype1 eq "reg")
                                         {
                                               $c .= ' ' x $indent . "$param1 = getchar();\n\n";
                                         }

                                         elsif($ptype1 eq "mem")
                                         { 
                                               $param1 =~ s/\[//;
                                               $c .= ' ' x $indent . "mem[$param1] = getchar();\n\n";
                                         }
                                         
                                         $badkode_idx += 1;
               };

               ($badkode_arr_ref->[$badkode_idx] eq '}') && do
               {
                                         $indent -= 6;
                                         $c .= ' ' x $indent . "}\n\n";
               };
 
               ($badkode_arr_ref->[$badkode_idx] eq '{') && do
               {
                                         if($param1 ne "!" && $param1 ne "+" && $param1 ne "-" && $param1 ne "=")
                                         {
                                               print "Bad comparison operator after { (token " . ($badkode_idx + 1) . ").\n";
                                               return 0;
                                         }

                                         if($param1 eq "=")
                                         {
                                            if($ptype2 eq "num")
                                            {
                                               print "{ does not accept a number as a parameter (token " . ($badkode_idx + 1) . ").\n";
                                            }

                                            elsif($ptype2 eq "reg")
                                            {
                                                  $c .= ' ' x $indent . "while($param2 == 0)\n";
                                                  $c .= ' ' x $indent . "{\n\n"; 
                                            }

                                            elsif($ptype2 eq "mem") 
                                            {
                                                  $param2 =~ s/\[//;
                                                  $c .= ' ' x $indent . "while(mem[$param2] == 0)\n";
                                                  $c .= ' ' x $indent . "{\n\n"; 
                                            }

                                            else
                                            {
                                               print "Bad parameter after ! in { (token " . ($badkode_idx + 1) . ").\n";
                                               return 0;
                                            }
                                         }
 
                                         elsif($param1 eq "-")
                                         {
                                            if($ptype2 eq "num")
                                            {
                                               print "{ does not accept a number as a parameter (token " . ($badkode_idx + 1) . ").\n";
                                            }

                                            elsif($ptype2 eq "reg")
                                            {
                                                  $c .= ' ' x $indent . "while($param2 < 0)\n";
                                                  $c .= ' ' x $indent . "{\n\n"; 
                                            }

                                            elsif($ptype2 eq "mem") 
                                            {
                                                  $param2 =~ s/\[//;
                                                  $c .= ' ' x $indent . "while(mem[$param2] < 0)\n";
                                                  $c .= ' ' x $indent . "{\n\n"; 
                                            }

                                            else
                                            {
                                               print "Bad parameter after ! in { (token " . ($badkode_idx + 1) . ").\n";
                                               return 0;
                                            }
                                         }
 
                                         elsif($param1 eq "+")
                                         {
                                            if($ptype2 eq "num")
                                            {
                                               print "{ does not accept a number as a parameter (token " . ($badkode_idx + 1) . ").\n";
                                            }

                                            elsif($ptype2 eq "reg")
                                            {
                                                  $c .= ' ' x $indent . "while($param2 >= 0)\n";
                                                  $c .= ' ' x $indent . "{\n\n"; 
                                            }

                                            elsif($ptype2 eq "mem") 
                                            {
                                                  $param2 =~ s/\[//;
                                                  $c .= ' ' x $indent . "while(mem[$param2] >= 0)\n";
                                                  $c .= ' ' x $indent . "{\n\n"; 
                                            }

                                            else
                                            {
                                               print "Bad parameter after ! in { (token " . ($badkode_idx + 1) . ").\n";
                                               return 0;
                                            }
                                         }
 
                                         elsif($param1 eq "!")
                                         {
                                            if($ptype2 eq "num")
                                            {
                                               print "{ does not accept a number as a parameter (token " . ($badkode_idx + 1) . ").\n";
                                            }

                                            elsif($ptype2 eq "reg")
                                            {
                                                  $c .= ' ' x $indent . "while($param2 != 0)\n";
                                                  $c .= ' ' x $indent . "{\n\n"; 
                                            }

                                            elsif($ptype2 eq "mem") 
                                            {
                                                  $param2 =~ s/\[//;
                                                  $c .= ' ' x $indent . "while(mem[$param2] != 0)\n";
                                                  $c .= ' ' x $indent . "{\n\n"; 
                                            }

                                            else
                                            {
                                               print "Bad parameter after ! in { (token " . ($badkode_idx + 1) . ").\n";
                                               return 0;
                                            }
                                         }

                                         $indent += 6;
                                         $badkode_idx += 2;
               };
          }

     }
     while(++$badkode_idx < scalar(@{$badkode_arr_ref}));

     return 1;
 }

 sub evaluate
 {
     my $param = $_[0];
     my $mem_ref = $_[1];

     if($param =~ /^[ab]/)
     {
        eval("\$param = \$$param");
     }

     elsif($param =~ /^\[[ab]/)
     {
           $param =~ s/^\[//;
           eval("\$param = \$mem_ref->[\$$param]");
           $param = ($param eq "") ? 0 : $param;
     }

     elsif($param !~ /^\d+/)
     {
        $param = '';
     }

     return $param;
 }

 sub typeof
 {
     my $param = $_[0];
     my $type;

     if($param =~ /^[ab]/)
     {
        $type = "reg";
     }

     elsif($param =~ /^\[[ab]/)
     {
        $type = "mem";
     }

     elsif($param =~ /^\d+/)
     {
        $type = "num";
     }

     return $type;
 }
