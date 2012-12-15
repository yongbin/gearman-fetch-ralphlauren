use 5.010;
use strict;
use warnings;

use Gearman::Client;
use Storable qw( thaw freeze );
use Const::Fast;
use UUID::Tiny;
use Redis;
use DateTime;

const my $PREFIX => 'angel-candy';

my ($uuid_str) = shift @ARGV;
my $client = Gearman::Client->new;
$client->job_servers('127.0.0.1:4730');

my $tasks  = $client->new_task_set;
$tasks->add_task( parse_page => freeze( [ $uuid_str ] ));
$tasks->wait;
