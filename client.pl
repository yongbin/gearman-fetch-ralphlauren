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

my $dt     = DateTime->now();
my $redis  = Redis->new( reconnect => 2, every => 100 );
my $client = Gearman::Client->new;
$client->job_servers('127.0.0.1:4730');

my $uuid     = create_UUID();
my $uuid_str = UUID_to_string($uuid);

$redis->set( join( ':', $PREFIX, 'uuid', $uuid_str ), $dt->epoch );

const my $url =>
  'http://www.ralphlauren.com/family/index.jsp?categoryId=2047535&pg=1';

my $tasks  = $client->new_task_set;
my $handle = $tasks->add_task(
    list_fetch => freeze( [ $uuid_str, $url ] ),
    {
        on_complete => sub {
                say "- start parsing";
                $tasks->add_task( parse_page => freeze( [ $uuid_str ] ));
        }
    }
);
$tasks->wait;
