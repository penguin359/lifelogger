use strict;
use warnings;
use Test::More;


use Catalyst::Test 'LifeLogger';
use LifeLogger::Controller::OAuth;

ok( request('/oauth/index?source=latitude')->is_redirect, 'Request should succeed' );
done_testing();
