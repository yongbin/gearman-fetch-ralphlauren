#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;

use Gearman::Worker;
use LWP::Simple qw/get/;
use List::Util qw(sum);
use Storable qw( freeze thaw );
use Template::Extract;
use Web::Query;

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
$worker->register_function(
    detail_fetch => \&detail_fetch
);
$worker->work while 1;

sub detail_fetch {
    my ($url) = @{ thaw( $_[0]->arg ) };
    say "URL : $url";
    my $obj = Template::Extract->new;
    my @result;

    my $document = get($url);

    my $stock_and_colors =
      $obj->extract( $product_detail_stock_colors, $document ) // {};
    my $general_information =
      $obj->extract( $product_detail_general_infomation, $document ) // {};

    foreach my $record ( @{ $stock_and_colors->{record} } ) {
        my $info    = {
            %{$record},
            %{$general_information},
        };
        push @result, $info;
    }
    return freeze( [ @result ] );
}
