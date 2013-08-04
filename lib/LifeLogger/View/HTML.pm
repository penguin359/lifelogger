package LifeLogger::View::HTML;
use Moose;
use namespace::autoclean;

extends 'Catalyst::View::TT';

__PACKAGE__->config(
    TEMPLATE_EXTENSION => '.tt',
    render_die => 1,
);

=head1 NAME

LifeLogger::View::HTML - TT View for LifeLogger

=head1 DESCRIPTION

TT View for LifeLogger.

=head1 SEE ALSO

L<LifeLogger>

=head1 AUTHOR

Loren M. Lang,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
