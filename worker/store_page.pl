#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;

use Gearman::Worker;
use LWP::Simple qw/get/;
use Storable qw( freeze thaw );
use Redis;
use UUID::Tiny;
use Const::Fast;

my $redis = Redis->new( reconnect => 2, every => 100 );
my $c = 1;

const my $PREFIX => 'angel-candy';
const my $url_format =>
  'http://www.ralphlauren.com/product/index.jsp?productId=%d';

my $worker = Gearman::Worker->new;
$worker->job_servers('127.0.0.1:4730');
$worker->register_function( store_page => \&store_page );
$worker->work while 1;

sub store_page {
    my ( $uuid, $product_id ) = @{ thaw( $_[0]->arg ) };
    my $url = sprintf( $url_format, $product_id );
    printf STDERR "[%05d] UUID:URL : %s:%s\n", $c++, $uuid, $url;

    my $key = join( ':', $PREFIX, $uuid, $url );

    $redis->set( $key => get($url) );
    $redis->set( join( ':', $PREFIX, 'product_id', $product_id ) => $key );
}
