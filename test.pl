use strict;
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test;
our @tests;
BEGIN { 
    @tests = glob("test_templates/*.tmpl");
    # idx starts at 1, and test1 is for loading
    my $num_tests = $#tests + 4;
    my $idx = 0;
    my %find_idx = map { ( $_, $idx++ ) } @tests;
    my @todos;
    #@todos = ("test_templates/sub_include.tmpl");
    #print "$_ = $find_idx{$_}\n" for @todos;


    # we add 2 similarly to above
    plan tests => $num_tests, todo => [ map { $find_idx{$_} + 2 } @todos  ] 
    #plan tests => $num_tests;
};
use Text::Macro;
ok(1); # If we made it this far, we're ok.

#########################

# Insert your test code below, the Test module is use()ed here so read
# its man page ( perldoc Test ) for help writing this test script.


#print "files: ", join( ", ", @tests ), "\n";

our %dontparse = map { ($_,$_) } qw( text.tmpl );



#get check-data
#my @keys = keys %tests;
our %check;
for my $key ( @tests )
{
    my $val = $key;
    $val =~ s/\.tmpl/\.chk/;

    $key =~ s!.*/!!;

    my $fh = new IO::File "$val" or die "Couldn't open file: $val";
    my $data = join("", $fh->getlines() );
    $data =~ s/\s+//sg unless exists $dontparse{$key};
    $check{$key} = $data;
    #print "check=[$check{$key}], key=[$key], data=[$data]\n";
}

#print "files: ", join(", ", @tests ), "\n";

sub test_file($)
{
    my ( $test ) = @_;
    print "Testing file $test\n";
    my ( $obj, $str );
    eval {
    $obj = new Text::Macro path => 'test_templates/', file => $test or die "Couldn't parse file: $test";
    }; if ( $@ ) { print "Could not compile: $@\n"; ok(0); return }

    eval {
        $str  = $obj->toString( 
        {
            true_var => 1,
            false_var => 0,
            undef_var => undef,
            for_block =>
            [
                { a => 1, b => 2 },
                { a => 3, b => 4 },
                { a => 5, b => 6 },
            ],
            value => 'dog',
        } );
    }; if ( $@ ) { 
        print "Could not render: $@\n"; 
        print "CODE\n$obj->{src}\nCODE\n";
        ok(0);
        return;
    }
    #print "CODE\n$obj->{src}\nCODE\n";

    $str =~ s/\s+//sg unless exists $dontparse{$test};
    ok( $str, $check{$test} );
} # end test_file

for my $key ( @tests )
{
    test_file( $key );
}

sub printTest
{
    print "print-test\n";
    my $test = shift;
    my $obj;
    eval {
        $obj = new Text::Macro path => 'test_templates/', file => $test or die "Couldn't parse file: $test";
    }; if ( $@ ) {
        print "Could not compile: $@\n"; ok(0); return;
    }

    eval {
        $obj->print( {} );
    }; if ( $@ ) {
        print "Could not render: $@\n"; 
        print "CODE\n$obj->{src}\nCODE\n";
        ok(0);
        return;
    }
    ok(1);
}

printTest("text.tmpl");

pipeTest("text.tmpl");

sub pipeTest
{
    my $test = shift;
    print "pipe-test\n";
    my $obj;
    eval {
        $obj = new Text::Macro path => 'test_templates/', file => $test or die "Couldn't parse file: $test";
    }; if ( $@ ) {
        print "Could not compile: $@\n"; ok(0); return;
    }

    my $str;
    eval {
        my $fname = "/tmp/test_$$";
        my $fh = new IO::File ">$fname";
        $obj->pipe( {}, $fh );
        $fh->close();
        $fh = new IO::File $fname;
        $str = join( "", $fh->getlines() );
        $fh->close();
        unlink $fname;
    }; if ( $@ ) {
        print "Could not render: $@\n"; 
        print "CODE\n$obj->{src}\nCODE\n";
        ok(0);
        return;
    }
    ok( $str, $check{$test} );
}
