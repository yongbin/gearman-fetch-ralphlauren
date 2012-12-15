#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;

use Gearman::Worker;
use LWP::Simple qw/get/;
use List::Util qw( min );
use Storable qw( freeze thaw );
use Template::Extract;
use Web::Query;
use Redis;
use UUID::Tiny;
use Const::Fast;
use JSON::XS;
use DateTime;

my $redis = Redis->new( reconnect => 2, every => 100 );
my $c = 1;

const my $PREFIX              => 'angel-candy';
const my $DOMAIN              => URI->new('http://www.ralphlauren.com');
const my %product_img_url_fmt => (
    'tiny'  => $DOMAIN . '/graphics/product_images/pPOLO2-%d_standard_t85.jpg',
    'small' => $DOMAIN
      . '/graphics/product_images/pPOLO2-%d_lifestyle_v360x480.jpg',
    'normal' => $DOMAIN . '/graphics/product_images/pPOLO2-%d_standard_dt.jpg',
);

const my $IMAGE_SERVER_HOST => "http://yongbin.imagehosting.com/";
const my $path_prefix       => "yongbin/";

my %polo_godo_cat_lookup = (
    qw/
      11593744 002002002003
      11593814 002002001003
      12646057 002002007004
      12669523 002002003004
      1767581  002002004001
      1767582  002002004002
      1767584  002002004004
      1767585  002002003001
      1767586  002002003002
      1767586  002002003002
      1767594  002002005004
      1767599  002002007004
      1767601  002002006002
      1767603  002002006004
      1767605  002002008002
      1767607  002002008004
      1815396  002002004003
      1882877  002002004004
      1890954  002002006001
      1890955  002002006001
      1890957  002002008001
      1890958  002002008001
      1892952  002002005
      1892953  002002007001
      1895475  002002005
      1895476  002002005
      1895477  002002007001
      1895478  002002007001
      1904289  002002006004
      1904291  002002008004
      1904293  002002005004
      1904298  002002004004
      1904300  002002003004
      1907196  002002004001
      1907197  002002003001
      1954785  002002006001
      1954813  002002008001
      1958847  002002006001
      1958848  002002008001
      1960675  002002006001
      1961589  002002005
      1961590  002002007001
      1988835  002002004001
      1988868  002002003001
      2032039  002002004002
      2032042  002002006002
      2032043  002002008002
      2047534  002002002001
      2047543  002002002003
      2047544  002002002004
      2047547  002002001003
      2047548  002002001001
      2047548  002002001003
      2047549  002002001004
      2047550  002002001004
      2058611  002002003004
      2073387  002002004001
      2073388  002002003001
      2124967  002002008001
      2143106  002002005002
      2143107  002002005003
      2143112  002002007002
      2143114  002002007003
      2194367  002002002004
      2249349  002002003003
      2250108  002002002004
      2250109  002002001004
      2292614  002002006001
      2292615  002002008001
      2461102  002002002003
      2461103  002002001003
      2462796  002002008001
      2462797  002002006001
      2746382  002002005002
      2746383  002002005002
      2746384  002002007002
      2746385  002002007002
      2794258  002002003003
      3214810  002002006004
      3214811  002002008004
      3214812  002002005004
      3214813  002002007004
      3714755  002002006002
      3714756  002002008002
      3714757  002002005002
      3714758  002002007002
      3714759  002002004002
      4216235  002002002001
      4216237  002002001001
      4216665  002002002001
      4216667  002002001001
      4450428  002002006003
      4450431  002002005003
      4450433  002002004003
      4450436  002002003003
      /
);

my $product_detail_stock_colors = << '.';
<SCRIPT LANGUAGE="JavaScript">
	itemMap = new Array();
	Scene7Map = new Array();
    var imageObj = null;
	
	
		[% FOREACH record %]
		/* Fill the itemMap JavaScript Array with sku information */
		itemMap[[% i %]] = { pid: '[% pid %]',sku: [% sku %],sDesc: "[% sDesc %]",sId: "[% sId %]",cDesc: "[% cDesc %]",cId: "[% cId %]",avail: "[% avail %]",price: "[% price %]",jdaStyle: "[% jdaStyle %]"};
	
	[% ... %]
	[% END %]
</script>
.

my $product_detail_general_infomation = << '.';
	<div class="itemheadernew">
			<div id="title2Banner" class="prodbanner">

					<img src="[% cat_url %]"
						width="100%"
						height="50"
						border="0"
						alt="[% cat_alt %]" title="[% cat_title %]">
				
</div>

			<div class="prodtitleLG">
				<h1>[% product_title %]</h1>
			</div>
			<div class="ProductPriceContainer">
			
				<span class="prodourprice">Price: &#036;[% product_price %]</span>
			
			
			</div>
			
			

			<div class="productStyleDiv" style="padding-bottom:2;">
				<span class="productStyle">Style #[% product_id %]</span>
			</div>
	</div>
	
.

my $worker = Gearman::Worker->new;
$worker->job_servers('127.0.0.1:4730');
$worker->register_function( parse_page => \&parse_page );
$worker->work while 1;

sub parse_page {
    my ($uuid) = @{ thaw( $_[0]->arg ) };
    printf STDERR " [%05d] UUID : %s\n", $c++, $uuid;
    my $obj = Template::Extract->new;
    my $dt  = DateTime->now();
    my @result;

    foreach my $k ( $redis->keys( join( ':', $PREFIX, $uuid ) . '*:http*' ) ) {
        my $document = $redis->get($k);

        my ( $url, $product_id ) = $k =~
          m{(http://www\.ralphlauren\.com/product/index\.jsp\?productId=(\d+))};

        my $stock_and_colors =
          $obj->extract( $product_detail_stock_colors, $document ) // {};
        my $general_information =
          $obj->extract( $product_detail_general_infomation, $document ) // {};

        my %cid_sku = cid_sku_lookup( $stock_and_colors->{record} );

        foreach my $record ( @{ $stock_and_colors->{record} } ) {
            my %info = (
                %{$record},
                %{$general_information},

         #----------------------------------------------------------------------
                url         => "$url",
                image_small => sprintf(
                    $product_img_url_fmt{small},
                    $cid_sku{ $record->{cId} }
                ),
                image_normal => sprintf(
                    $product_img_url_fmt{normal},
                    $cid_sku{ $record->{cId} }
                ),
                image_tiny => sprintf(
                    $product_img_url_fmt{tiny},
                    $cid_sku{ $record->{cId} }
                ),

         #----------------------------------------------------------------------
                s_goodscd => $record->{pid},
                s_goodsnm => sprintf( "[%s] %s",
                    uc( $general_information->{cat_title} ),
                    $general_information->{product_title} ),
                s_goodscate =>
                , # join( '|', $polo_godo_cat_lookup{$categoryId} =~ $godo_cat_pattern ),
                s_shortdesc => 'polo',
                s_longdesc  =>,
                s_img_i     => join( '/', $IMAGE_SERVER_HOST, $path_prefix, ),
                s_img_s     =>,
                s_img_m     =>,
                s_img_l     =>,
                s_regdt     => join( ' ', $dt->ymd, $dt->hms ),
                s_open      =>,
                s_optnm     =>,
                s_opts      =>,
                s_ex1       =>,
                s_ex_title  =>,
            );

            $redis->set( join( ':', $PREFIX, $uuid, 'json', $product_id ),
                encode_json( \%info ) );
            $redis->hset( join( ':', $PREFIX, $uuid, 'data', $product_id ),
                $_, $info{$_}, sub { } )
              for keys %info;
            $redis->wait_all_responses;
        }
    }
}

sub cid_sku_lookup {
    my ($array_ref) = @_;

    my %h;
    foreach (@$array_ref) {
        push @{ $h{ $_->{cId} } }, $_->{sku};
    }

    my %return = map { $_ => min @{ $h{$_} } } keys %h;
    return %return;
}
