# --
# Kernel/System/InstanceAsRepository.pm - lib package manager
# Copyright (C) 2001-2010 OTRS AG, http://otrs.org/
# --
# $Id: InstanceAsRepository.pm,v 1.119 2010/09/23 08:44:35 mb Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::InstanceAsRepository;

use strict;
use warnings;

use Kernel::System::Package;

use vars qw($VERSION $S);
$VERSION = qw($Revision: 1.119 $) [1];

=head1 NAME

Kernel::System::InstanceAsRepository - to manage application packages/modules

=head1 SYNOPSIS

All functions to manage application packages/modules.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object

    use Kernel::Config;
    use Kernel::System::Encode;
    use Kernel::System::Log;
    use Kernel::System::Main;
    use Kernel::System::DB;
    use Kernel::System::Time;
    use Kernel::System::InstanceAsRepository;

    my $ConfigObject = Kernel::Config->new();
    my $EncodeObject = Kernel::System::Encode->new(
        ConfigObject => $ConfigObject,
    );
    my $LogObject = Kernel::System::Log->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
    );
    my $MainObject = Kernel::System::Main->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
        LogObject    => $LogObject,
    );
    my $DBObject = Kernel::System::DB->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
        LogObject    => $LogObject,
        MainObject   => $MainObject,
    );
    my $TimeObject = Kernel::System::Time->new(
        ConfigObject => $ConfigObject,
        LogObject    => $LogObject,
    );
    my $InstanceAsRepositoryObject = Kernel::System::InstanceAsRepository->new(
        LogObject    => $LogObject,
        ConfigObject => $ConfigObject,
        TimeObject   => $TimeObject,
        DBObject     => $DBObject,
        EncodeObject => $EncodeObject,
        MainObject   => $MainObject,
    );

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for my $Object (qw(DBObject ConfigObject LogObject TimeObject MainObject EncodeObject)) {
        $Self->{$Object} = $Param{$Object} || die "Got no $Object!";
    }

    # create needed objects
    $Self->{PackageObject} = Kernel::System::Package->new( %{$Self} );

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

    for my $Needed (qw(Name Version)) {
        if ( !$Param{$Needed} ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    return if !$Self->{DBObject}->Prepare(
        SQL  => 'SELECT approved FROM instance_package_repository '
            . 'WHERE name = ? AND version = ? AND approved = version',
        Bind => [ \$Param{Name}, \$Param{Version} ],
    );

    my $IsApproved;
    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {
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

    return if !$Self->{DBObject}->Prepare(
        SQL => 'SELECT pr.id, pr.name, pr.version, pr.approved, pr.content '
            . 'FROM instance_package_repository pr '
            . 'ORDER BY pr.name, pr.create_time',
    );

    my %PackagesSeen;
    my @Data;
    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {
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

    return if !$Self->{DBObject}->Prepare(
        SQL => 'SELECT pr.id, pr.name, pr.version, pr.content '
            . 'FROM package_repository pr '
            . 'ORDER BY pr.name, pr.create_time',
    );

    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {
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

            my %Structure = $Self->{PackageObject}->PackageParse(
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

    # check needed stuff
    for my $Needed (qw(PackageID UserID)) {
        if ( !$Param{$Needed} ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message => "Need $Needed",
            );
            return;
        }
    }

    return if !$Self->{DBObject}->Prepare(
        SQL   => 'SELECT name, version, content FROM package_repository WHERE id = ?',
        Bind  => [ \$Param{PackageID} ],
        Limit => 1,
    );

    my %Info;
    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {
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
    return $Self->{DBObject}->Do(
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

    # check needed stuff
    for my $Needed (qw(PackageID)) {
        if ( !$Param{$Needed} ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message => "Need $Needed",
            );
            return;
        }
    }

    # db access
    return $Self->{DBObject}->Do(
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

    if ( $Param{PackageID} ) {
        my $SQL = 'SELECT name, version FROM instance_package_repository WHERE id = ?';

        $Self->{DBObject}->Prepare(
            SQL   => $SQL,
            Bind  => [ \$Param{PackageID} ],
            Limit => 1,
        );

        while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {
            $Param{Name}    = $Row[0],
            $Param{Version} = $Row[1],
        }
    }

    # check needed stuff
    for my $Needed (qw(Name Version)) {
        if ( !defined $Param{$Needed} ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message => "$Needed not defined!",
            );
            return;
        }
    }

    # db access
    $Self->{DBObject}->Prepare(
        SQL => 'SELECT content FROM instance_package_repository WHERE name = ? AND version = ?',
        Bind => [ \$Param{Name}, \$Param{Version} ],
    );
    my $Package = '';
    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {
        $Package = $Row[0];
    }
    if ( !$Package ) {
        $Self->{LogObject}->Log(
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

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut

=head1 VERSION

$Revision: 1.119 $ $Date: 2010/09/23 08:44:35 $

=cut
