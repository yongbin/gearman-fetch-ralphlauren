#!/usr/bin/env perl
use 5.010;
use Data::Dumper;
use Gearman::Client;
use Gearman::Worker;
use LWP::Simple qw( get );
use Storable qw( freeze thaw );
use Template::Extract;
use Web::Query;

my $worker = Gearman::Worker->new;
$worker->job_servers('127.0.0.1:4730');
$worker->register_function( list_fetch => \&list_fetch, );
$worker->work while 1;

sub list_fetch {
    my ( $uuid, $url ) = @{ thaw( $_[0]->arg ) };
    my $client = Gearman::Client->new;
    $client->job_servers('127.0.0.1:4730');
    my $tasks = $client->new_task_set;

    say STDERR "- list_fetch start";

    my $pattern = qr{/product/index\.jsp\?productId=(\d+)$};
    my @list;

    my $html                    = get($url);
    my $PRODUCT_NUMBER_PER_PAGE = 15;

    foreach my $id ( 1 .. $PRODUCT_NUMBER_PER_PAGE ) {
        wq($html)->find("div#staticImg$id > a")->each(
            sub {
                my ($product_id) = $_->attr('href') =~ $pattern;

                $tasks->add_task(
                    store_page => freeze( [ $uuid, $product_id ] ),
                    {
                        on_complete => sub { }
                    }
                );
            }
        );
    }

=pod
                $tasks->add_task(
                    detail_fetch =>
                      freeze( [ sprintf $url_pattern, $product_id ] ),
                    {
                        on_complete => sub {
                            say 'detail_fetch complete';
                            print Dumper \@{ thaw( ${ $_[0] } ) };
                          }
                    }
                );
=cut

    say STDERR "- list_fetch end";
}
