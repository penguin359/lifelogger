use strict;
use warnings;
use Test::More;


use Catalyst::Test 'LifeLogger';
use LifeLogger::Controller::OAuth;

ok( request('/oauth')->is_success, 'Request should succeed' );
done_testing();
