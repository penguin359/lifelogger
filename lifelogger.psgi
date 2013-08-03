use strict;
use warnings;

use LifeLogger;

my $app = LifeLogger->apply_default_middlewares(LifeLogger->psgi_app);
$app;

