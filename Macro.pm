########################################
# Module: Text::Macro
# Purpose: A text macro-language almost identical to Text::FastTemplate
# Author: Michael Maraist <maraist@udel.edu>
# Derived from: Text::FastTemplate
########################################

package Text::Macro;
use strict;
use integer;
use IO::File;

our %cache;

require 5.006;
our $VERSION = '0.02';

use fields qw( filename path code src );

########################################
# Function: new
########################################
sub new {
  my $self = shift;
  my %args = @_;
  my $filename = $args{file} or die "No file-name provided";
  my $path = "";
  if ( exists $args{path} ) {
      $path = $args{path};
      if ( ! $path =~ m!/$! ) {
          $path .= "/";
      }
  }

  if ( exists $cache{ $filename } ) {
        return $cache{ $filename };
  }

  my Text::Macro $this = fields::new( $self );

  $this->{filename} = $filename;
  $this->{path} = $path;

  $this->parse( );
  $cache{ $filename } = $this;
  return $this;
} # end new

########################################
# Function: readFile
# Purpose:  recursive file-reader.  Actively handles include-directives
# IN:       file-name
# Throws:   couldn't open file
########################################
sub readFile($$)
{
    my Text::Macro $this = shift;
    my $file = shift;
    my $file_name = $this->{path} . $file;

    my $fh = new IO::File $file_name
        or die "Could not load file: $file_name";
    my $idx = 1;
    return map {
         /^\s*\#include\s+(.*)\n$/ ? $this->readFile( $1 ) : [ $_, $idx++, $file  ];
    } $fh->getlines();
} # end readFile

########################################
# 
########################################
sub compileError($$)
{
    my ( $msg, $block ) = @_;
    print STDERR "Error: $msg; $block->[1] $block->[2]: $block->[0]";
    exit(-1);
} # end compileError

########################################
# Function: getText
# Purpose:  get the next raw string piece of text
########################################
sub getTextBlock($)
{
    my ( $blocks ) = @_;
    my $line_chunks;
    # extract line chunks (consolidating with previous line if possible.
    $_ = $blocks->[ $#$blocks ];
    if ( ref( $_ ) ne "ARRAY" ) {
        $line_chunks = [];
        push @$blocks, $line_chunks;
    } else {
        $line_chunks = $_;
    }
    
    return $line_chunks;
} # end getTextBlock

########################################
# Function: concatText
# Purpose:  concatenate text to an existing print-statement
########################################
sub concatText($$)
{
    my ( $line_block, $txt ) = @_;
    $txt =~ s/\'/\\\'/g;
    my $str = $line_block->[-1];
    if ( defined $str && substr( $str, -1, 1 ) eq "'") {
        # previous piece of text was string; concat
        substr( $str, -1, 0, $txt );
        $line_block->[-1] = $str;
    } else {
        push @$line_block, "'$txt'";
    }
} # end concatText

##################################################
# Function: parse
# Purpose:  convert the input template file into perl code
# ToDo:     Make sure that the input is properly escaped
##################################################
sub parse($)
{
    my Text::Macro $this = shift;

    my @lines = $this->readFile( $this->{filename} );

    my @blocks;
    my @pre_blocks;
    my @stack;
    my @switch_stack;
    my $line;
    my %subs;
    my $for_sep = "";

    #for my $line_block ( @lines ) {
    for ( my $line_idx = 0; $line_idx <= $#lines ; $line_idx++ ) { 
        my $line_block = $lines[$line_idx];

        my $line = $line_block->[0];
      
        # Determine if we're a command
        if ( my ( $cmd, $cond ) = $line =~ /
            ^ \s*\#( if | for | elsif | else  | endif | endfor | comment | sub | callsub | pre | switch | case | endswitch | default ) \s* (.*) \n $
            /x ) {
            # We are a command
            if ( $cmd eq "if" ) {
                compileError( "No if conditional", $line_block )
                    unless $cond;

                # pre-process cond
                $cond =~ s/\#\#(\w+)\#\#/\$scope->{$1}/g;

                push @blocks, "if ( $cond ) {\n";
                push @stack, "i";
            } elsif ( $cmd eq "switch" ) {
                my ( $var ) = $cond =~ /\#\#(\w+)\#\#/;
                compileError( "No switch argument", $line_block )
                    unless $var;

                push @switch_stack, [ $var, 1 ];
                push @stack, "s";
            } elsif ( $cmd eq "endswitch" ) {
                compileError( "Exiting $stack[-1] when still in switch", $line_block )
                    unless $stack[-1] eq "s" || $stack[-1] eq "d";
                pop @stack;
                push @blocks, "}\n" unless $switch_stack[-1][1];
                pop @switch_stack;
            } elsif ( $cmd eq "case" ) {
                my ( @syms ) = $cond =~ /(\"[^\"]+\")/g;
                compileError( "No conditional value", $line_block )
                    unless @syms;
                compileError( "case with no switch", $line_block )
                    unless @switch_stack;
                my $switch_item = $switch_stack[-1];
                my $sym_str = "(" . join( ') || (', map { "\$scope->{$switch_item->[0]} eq $_" } @syms ) . ")";
                if ( $switch_item->[1] ) {
                    push @blocks, "if ( $sym_str ) {\n";
                    $switch_item->[1] = 0;
                } else {
                    push @blocks, "} elsif ( $sym_str ) {\n";
                }
            } elsif ( $cmd eq "default" ) {
                compileError( "case with no switch", $line_block )
                    unless @switch_stack;
                my $switch_item = $switch_stack[-1];
                if ( $switch_item->[1] ) {
                    #push @blocks, "{\n";
                    #$switch_item->[1] = 0;
                } else {
                    push @blocks, "} else {\n";
                }
                $stack[-1] = "d";
            } elsif ( $cmd eq "pre" ) {
                my $line_chunks;
                $line_chunks = getTextBlock(\@blocks);
                # Gobble up the remainder of the sub for later use
                for ( $line_idx++ ; $line_idx <= $#lines && ( ( $line = ($line_block = $lines[$line_idx])->[0] ) !~ /^\s*\#endpre/ ) ; $line_idx++ ) {
                    concatText( $line_chunks, $line );
                } 
            
            } elsif ( $cmd eq "sub" ) {
                my ($sub_name) = $cond =~ /(\w+)/;
                compileErrot( "No sub-name", $line_block )
                    unless $sub_name;
                my @sub_data = ();
                # Gobble up the remainder of the sub for later use
                for ( $line_idx++ ; $line_idx <= $#lines && ( ( $line = ($line_block = $lines[$line_idx])->[0] ) !~ /^\s*\#endsub/ ) ; $line_idx++ ) {
                    push @sub_data, $line_block;
                } 
                $subs{$sub_name} = \@sub_data;
            } elsif ( $cmd eq "callsub" ) {
                my ($sub_name) = $cond =~ /(\w+)/;
                compileError( "No sub-name", $line_block )
                    unless $sub_name;
                splice( @lines, $line_idx + 1, 0, @{$subs{$cond}} );
            } elsif ( $cmd eq "for" ) {
                my ($var) = $cond =~ /\#\#(\w+)\#\#/
                    or compileError( "No conditional", $line_block );
                $for_sep = "";
                if ( $cond =~ /; sep="(.*?)"/ ) {
                    $for_sep = "(\$counter == \@loop_var ? \"\" : \"$1\" )";
                }
                push @stack, "f";
                #ZZZ make size, idx, and comma exist only if used
                push @blocks, <<EOS;
\{ my \$old_scope = \$scope;
  my \@loop_var = (exists \$scope->{$var} && ref(\$scope->{$var}) eq "ARRAY" ) ? \@{\$scope->{$var}} : ();
  my \$counter = 0;
  for my \$el ( \@loop_var ) \{
    \$scope = defined(\$el) && ref(\$el) eq "HASH" ? \$el : {};
    \$scope->{${var}_SIZE} = scalar \@loop_var;
    \$scope->{${var}_IDX} = ++\$counter;
    #\$scope->{${var}_COMMA} = \$counter == \@loop_var ? "" : ",";

EOS
        } elsif ( $cmd eq "else" ) {
            compileError( "else not level with if", $line_block )
              unless $stack[ $#stack ] eq "i";

        $stack[ $#stack ] = "e"; # pop/push
        push @blocks, "} else {\n";
      } elsif ( $cmd eq "elsif" ) {
        compileError( "No conditional", $line_block )
          unless $cond;
        compileError( "elsif not level with if", $line_block )
          unless $stack[ $#stack ] eq "i";

        # pre-process cond
        $cond =~ s/\#\#(\w+)\#\#/\$scope->{$1}/g;

        push @blocks, "} elsif ( $cond ) {\n";
      } elsif ( $cmd eq "endif" ) {
        $_ = $stack[ $#stack ];
        compileError( "endif not level with if", $line_block )
          unless $_ eq "i" || $_ eq "e";
        pop @stack;
        push @blocks, "}\n";
      } elsif ( $cmd eq "endfor" ) {
        compileError( "endfor not level with for", $line_block )
          unless $stack[ $#stack ] eq "f";
        pop @stack;
        if ( $for_sep ) {
            my $line_block = getTextBlock( \@blocks );
            push @$line_block, $for_sep;
            #concatText( $line_block, $for_sep );
        }
        push @blocks, "}\n\$scope=\$old_scope;\n}\n";
      } elsif ( $cmd eq "comment" ) {
        # ignore line
      } else {
        compileError( "Invalid command state", $line_block );
      }
    } else { # if command
      # We weren't a command
        my $line_chunks = getTextBlock( \@blocks );

      # replace "##\w+##" with a variable insertion point or raw text
      for ( split( /(\#\#\w+\#\#)/, $line ) ) {
        if ( /^\#\#(\w+)\#\#$/ ) {
          push @$line_chunks, "\$scope->{$1}";
        } else {
            concatText( $line_chunks, $_ );
        }
      } 
    } # end else (not command)
  } # end readlines

    die "stack not unraveled at end of input"
        if @stack;

    # Convert text-chunks to print statements
    for my $block ( @blocks ) {
        if ( ref( $block ) eq "ARRAY" ) {
            for( @$block ) {
                s!\\\n!!;
            }
            $block = "\$fh->( " . join( ", ", @$block ) . ");\n";
        }
    }

  my @code = ( 
              "sub {\nno warnings;\nmy \$scope = shift;\nmy \$fh = shift;\n",
              @blocks,
              "};\n"
             );
  my $src = "@code";
  $this->{src} = $src;
  my $code = eval $src;

  $this->{code} = $code;
} # end parse

########################################
# Function: print
########################################
sub print($$) {
  my Text::Macro $this = shift;
  my $data = shift;
  die "Compilation error"
      unless $this->{code};
  no warnings;
  $this->{code}->( $data, sub { print @_; });
} # end print

sub pipe($$$) {
  my Text::Macro $this = shift;
  my $data = shift;
  my $fh = shift;

  die "Compilation error"
      unless $this->{code};
  no warnings;
  $this->{code}->( $data, sub { print $fh @_;  } );
} # end pipe

sub toString($$) {
  my ( $this, $data ) = @_;
  die "Compilation error"
      unless $this->{code};

  my @contents; 
  no warnings;
  $this->{code}->( $data, sub {  push @contents, @_; } );
  return join( "", @contents );
} # end toString

1;

__END__

=pod

=head1 TITLE Text::Macro

=head1 FORWARD

This module is template facility who's focus is on generating code such as c, java or sql.  While generating perl code is also possible, there is a potential conflict between the control-symbol and the perl comment symbol.

Perl is excelent at manipulating text, and it begs the question why one would need such a tool.  The answer is that good code design should be such that applications should not have to be modified so as to make configuration changes.  Thus external configuration files/data is used.  However, if these files are read in as perl-code, then simple errors could crash the whole application (or provide subtle security risks).  Further, it is often desired to invert the control flow and text-data (namely, make the embedded strings primary, and control-flow secondary).  This is the ASP model, and for 90% HTML, 10% code, this works great.

This module supports many control facilities which directly translate into perl-control facilities (e.g. inverting the ASP-style code back into perl-style behind the scenes).  The inversion process is cached in a simple user object.

The module was initially inspired by Text::FastTemplate by Robert Lehr, who's module didn't completely fullfill my needs.

=head1 FEATURES

 * fast, simple, robust
 * code-generating-centric feature-set
 * substitutions stand-out from template
 * macro-code embedded in text
 * OOP
 * external and internal includes (for clearifying complex control-flow)
 * scoped variable-substitutions
 * line-based processing (like cpp)
 * usable error messages

=head1 SYNOPSIS

=head2 Sample code

 use Text::Macro;
 
 my $parser = new Text::Macro path => "templates", file => "sql.template";
  
 # print macro substitutions
 $parser->print( { var1 => 'val1', var2 => 'val2' } );
 
 use IO::File;
 my $fh = new IO::File ">out.file";
 
 # direct the output to the given file
 $parse->pipe( 
    { 
      table_name => $table_name,
      f_primary_key => 1,
      primary_key => 'id',
      col_fields => 
        [
           {
              col_name => 'colName1',
              col_type => 'colType1'
           },
           {
              col_name => 'colName2',
              col_type => 'colType2'
           }
        ]
    }, $fh );

  my $str = $parse->toString( { .. } );

=head2 Sample macro

 #sub pk_block
  #if ##primary_key##
   primary key ##primary_key##,
  #elsif ##f_define_id##
   primary key id,
  #endif
 #endsub
 #comment --------------

 #include licence_agreement.template

 create table ##table_name## (

 #callsub pk_block

 #comment Produce the appropriate fields
 #for ##col_fields##; sep=",\n"
   ##col_name## ##col_type##; ' \
   IDX = ##col_fields_IDX## of ##col_fields_SIZE##\
 #endfor

 );

=head1 DESCRIPTION METHODS

=head2  new( path => 'path-to-files', file => 'particular template-name' )

This creates a new optimized parser.. This actually generates perl code to run the data so invocations should be speedy.

This throws an exception if the file can't be found.

=head2 $obj->print( { subs vals } )

This runs the macro, substituting the values specified in the input hash parameter.  Note that it must be a hash-ref or an exception will be thrown.  It's possible that the rendered code could throw an exception, but this would be considered a bug in the parser.

=head2 $obj->pipe( { subs vals }, $file_handle )

This is identical to print($) but redirects the output to the file-handle.  It is assumed that IO::File is used.

=head2 $obj->toString( { subs vals } )

This method allows the rendered text to be directly captured.

=head1 DESCRIPTION MACRO format

Text is passed unmodified except for '#' pre-processor directives.  The easiest format is the "##var_name##" directive which searches for a context hash-value with the appropriate hash-key name.  In the outer scope, the context is the passed hash-ref keys/values.  Within a for-loop, the context changes as described below.

Lines in the macro-file that begin with a '#directive' are flow-control statements.  Valid statements are ( #if ##cond_var## | #else | #elsif ##cond_var## | #endif | #for ##list_var## | #endfor | #include file_name | #comment | #sub sub_name | #endsub | #callsub sub_name | #pre | #endpre | #switch ##var_name## | #case "value1", "value2".. | #default | #endswitch).  Some of the flow-control directives take a variable and process on it.  Non-recognized statements are passed as-is.

The if/elsif/else/endif statements simply insert the contents of the hash-value into a perl "if ( $context->{$var_name} ) {" block, so potentially complex statements can be achieved.  In general, however, the logic-computation should be pre-computed and simply provide a boolean flag.

For "for"/"endfor" directives, the variable should be an array of hashes (technically an array-ref of hash-refs).  It will iterate over the array and update an index of the name "varname_IDX" (which can be used as a regular insertion variable). Other custom variables are "varname_SIZE" (which contains the max IDX value).  The context of the insertion variables will change to be the contents of the sub-hash.  This is important since variables of the previous scope are not available.  Any fields desired at this point should be duplicated in the setup process.

The include directive simply replaces that line with the contents of the file_name (exception if not found).  This is a recursive process.

The 'comment' directive simply ignores that line

The 'xxsub' routines are a sort of local include.  They are good for extracting complex pieces out into separate blocks of code/template-data.  At the moment, no parameters may be passed.  The format is to declare a block with #sub {sub-name} / #endsub block, then invoke it with #callsub {sub-name} just like an include statement.

The 'pre' block passes values exactly as is (with no hash-substution).  The only thing that it can't pass is #endpre.  This could be good to pass perl-comments.

The 'switch' / 'case' / 'default' blocks are merely for convinience and deviate from the c-language style.  In function they are readibility structures which get expanded out to:
 if ( ##cond_var## eq "case_value" ) {
 } elsif ( .. ) {
 } else {
 }
Because of this, c-style break-statements and fall-throughs don't exist.  Further, in c, the comparison is between integers.  Here it is between strings (which _can_ work for numbers, so long as there's no stringification ambiguity.  Here is an example:
 #switch ##data_type##
 #case "boolean"
   Do somethign with boolean
 #case "int", "integer"
   Do something with type integer
 #default
   If neither of the above special cases, then do this
 #endswitch

If a line ends with "\\\n" (meaning back-slash followed by a carrage return), then the carrage return is stripped.  This is useful for hash-commands that would otherwise require carriage returns to be displayed.  For example:
 pre-text \
 #for ##var##
  data ##val##\
 #endfor
 post-text


=head1 BUGS

you can't declare a sub within a sub (and this includes an include)

=head1 TODO

Allow sub-contexts the access parent-contexts as defaults.  Currently considered too much overhead.

Provide better error handling (getting there)

For performance enhancement, extract the hash-values into local variables when more than one instance is used. Since this slows down the parsing stage, this might be considered an input parameter flag to new.

=head1 SEE ALSO

=head1 AUTHOR

 Artistic License
 Copyright (C) 2002 Michael Maraist <maraist@udel.edu>

=cut

#
# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
#
