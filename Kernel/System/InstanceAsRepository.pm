# --
# Kernel/System/InstanceAsRepository.pm - lib package manager
# Copyright (C) 2014 Perl-Services.de, http://perl-services.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::InstanceAsRepository;

use strict;
use warnings;

our @ObjectDependencies = qw(
    Kernel::System::Log
    Kernel::System::DB
    Kernel::System::Package
);

our $VERSION = 0.01;

=head1 NAME

Kernel::System::InstanceAsRepository - to manage application packages/modules

=head1 SYNOPSIS

All functions to manage application packages/modules.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=item PackageIsApproved()

checks if a given package is approved.

    my $IsApproved = $Object->PackageIsApproved(
        Name    => 'Testpackage',
        Version => '1.2.3',
    );

=cut

sub PackageIsApproved {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');

    for my $Needed (qw(Name Version)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    return if !$DBObject->Prepare(
        SQL  => 'SELECT approved FROM instance_package_repository '
            . 'WHERE name = ? AND version = ? AND approved = version',
        Bind => [ \$Param{Name}, \$Param{Version} ],
    );

    my $IsApproved;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $IsApproved = $Row[0];
    }

    return $IsApproved;
}

=item RepositoryList()

returns a list of repository packages

    my @List = $InstanceAsRepositoryObject->RepositoryList();

=cut

sub RepositoryList {
    my ( $Self, %Param ) = @_;

    my $LogObject     = $Kernel::OM->Get('Kernel::System::Log');
    my $DBObject      = $Kernel::OM->Get('Kernel::System::DB');
    my $PackageObject = $Kernel::OM->Get('Kernel::System::Package');

    return if !$DBObject->Prepare(
        SQL => 'SELECT pr.id, pr.name, pr.version, pr.approved, pr.content '
            . 'FROM instance_package_repository pr '
            . 'ORDER BY pr.name, pr.create_time',
    );

    my %PackagesSeen;
    my @Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $IsApproved = ( $Row[3] && $Row[3] eq $Row[2] ) ? $Row[3] : 0;
        my %Info = (
            PackageID => $Row[0],
            Name      => { Content => $Row[1] },
            Version   => { Content => $Row[2] },
            Approved  => { Content => $IsApproved },
            Content   => { Content => $Row[4] },
        );

        $PackagesSeen{ $Row[1] . '-' . $Row[2] }++;

        push @Data, \%Info;
    }

    return if !$DBObject->Prepare(
        SQL => 'SELECT pr.id, pr.name, pr.version, pr.content '
            . 'FROM package_repository pr '
            . 'ORDER BY pr.name, pr.create_time',
    );

    while ( my @Row = $DBObject->FetchrowArray() ) {
        next if $PackagesSeen{ $Row[1] . '-' . $Row[2] };
        my %Info = (
            PackageID => $Row[0],
            Name      => { Content => $Row[1] },
            Version   => { Content => $Row[2] },
            Approved  => { Content => 0 },
            Content   => { Content => $Row[4] },
        );

        push @Data, \%Info;
    }

    my %MaxVersions;

    for my $Key ( keys %PackagesSeen ) {
        my ($Name,$Version) = split /-/, $Key;
        my $Numified        = sprintf "%03d%04d%04d", split /\./, $Version;
        if ( !$MaxVersions{$Name} || $MaxVersions{$Name} < $Numified ) {
            $MaxVersions{$Name} = $Numified;
        }
    }

    for my $Entity (@Data) {
        if ( $Entity->{Content}->{Content} ) {
            my $Approved  = $Entity->{Approved}->{Content};
            my $PackageID = $Entity->{PackageID};

            my %Structure = $PackageObject->PackageParse(
                String => \$Entity->{Content}->{Content},
            );

            my $Numified = sprintf "%03d%04d%04d", split /\./, $Structure{Version}->{Content};
            if ( $Param{Distinct} && $Numified != $MaxVersions{ $Entity->{Name}->{Content} } ) {
                $Approved = 0;
            }

            $Entity = {
                %Structure,
                Approved  => { Content => $Approved },
                PackageID => $PackageID,
            };
        }
    }

    return @Data;
}

=item PackageApprove()

approve a package from local repository

    my $InstanceAsRepository = $InstanceAsRepositoryObject->PackageApprove(
        PackageID => 123,
        UserID    => 10,
    );

=cut

sub PackageApprove {
    my ( $Self, %Param ) = @_;

    my $LogObject     = $Kernel::OM->Get('Kernel::System::Log');
    my $DBObject      = $Kernel::OM->Get('Kernel::System::DB');

    # check needed stuff
    for my $Needed (qw(PackageID UserID)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message => "Need $Needed",
            );
            return;
        }
    }

    return if !$DBObject->Prepare(
        SQL   => 'SELECT name, version, content FROM package_repository WHERE id = ?',
        Bind  => [ \$Param{PackageID} ],
        Limit => 1,
    );

    my %Info;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        %Info = (
            Name    => $Row[0],
            Version => $Row[1],
            Content => $Row[2],
        );
    }

    return if !%Info;

    return if $Self->PackageIsApproved(
        Name    => $Info{Name},
        Version => $Info{Version},
    );

    # db access
    return $DBObject->Do(
        SQL => 'INSERT INTO instance_package_repository ( approved, name, version, content, '
            . 'package_id, create_time, create_by, change_time, change_by ) '
            . 'VALUES (?,?,?,?,?,current_timestamp,?,current_timestamp,?)',
        Bind => [
            \$Info{Version},
            \$Info{Name},
            \$Info{Version},
            \$Info{Content},
            \$Param{PackageID},
            \$Param{UserID},
            \$Param{UserID},
        ],
    );
}

=item PackageRevoke()

revoke approval of a package from local repository

    my $InstanceAsRepository = $InstanceAsRepositoryObject->PackageRevoke(
        PackageID => 123,
    );

=cut

sub PackageRevoke {
    my ( $Self, %Param ) = @_;

    my $LogObject     = $Kernel::OM->Get('Kernel::System::Log');
    my $DBObject      = $Kernel::OM->Get('Kernel::System::DB');

    # check needed stuff
    for my $Needed (qw(PackageID)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message => "Need $Needed",
            );
            return;
        }
    }

    # db access
    return $DBObject->Do(
        SQL => 'DELETE FROM instance_package_repository WHERE id = ?',
        Bind => [ \$Param{PackageID} ],
    );
}

=item RepositoryGet()

get a package from local repository

    my $Package = $PackageObject->RepositoryGet(
        Name    => 'Application A',
        Version => '1.0',
    );

    my $PackageScalar = $PackageObject->RepositoryGet(
        Name    => 'Application A',
        Version => '1.0',
        Result  => 'SCALAR',
    );

=cut

sub RepositoryGet {
    my ( $Self, %Param ) = @_;

    my $LogObject     = $Kernel::OM->Get('Kernel::System::Log');
    my $DBObject      = $Kernel::OM->Get('Kernel::System::DB');

    if ( $Param{PackageID} ) {
        my $SQL = 'SELECT name, version FROM instance_package_repository WHERE id = ?';

        $DBObject->Prepare(
            SQL   => $SQL,
            Bind  => [ \$Param{PackageID} ],
            Limit => 1,
        );

        while ( my @Row = $DBObject->FetchrowArray() ) {
            $Param{Name}    = $Row[0],
            $Param{Version} = $Row[1],
        }
    }

    # check needed stuff
    for my $Needed (qw(Name Version)) {
        if ( !defined $Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message => "$Needed not defined!",
            );
            return;
        }
    }

    # db access
    $DBObject->Prepare(
        SQL => 'SELECT content FROM instance_package_repository WHERE name = ? AND version = ?',
        Bind => [ \$Param{Name}, \$Param{Version} ],
    );
    my $Package = '';
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Package = $Row[0];
    }
    if ( !$Package ) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => "No such package $Param{Name}-$Param{Version}!",
        );
        return;
    }

    if ( $Param{Result} && $Param{Result} eq 'INFO' ) {
        return (
            Package => $Package,
            Name    => sprintf( "%s-%s.opm", $Param{Name}, $Param{Version} ),
        );
    }
    elsif ( $Param{Result} && $Param{Result} eq 'SCALAR' ) {
        return \$Package;
    }

    return $Package;
}

1;


=back

=head1 TERMS AND CONDITIONS

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
