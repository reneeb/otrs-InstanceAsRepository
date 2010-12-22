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
        SQL  => 'SELECT approved FROM package_repository '
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

    $Self->{DBObject}->Prepare(
        SQL => 'SELECT id, name, version, approved, content '
            . 'FROM package_repository ORDER BY name, create_time',
    );

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

        push @Data, \%Info;
    }

    for my $Entity (@Data) {
        if ( $Entity->{Content}->{Content} ) {
            my $Approved  = $Entity->{Approved}->{Content};
            my $PackageID = $Entity->{PackageID};

            my %Structure = $Self->{PackageObject}->PackageParse(
                String => \$Entity->{Content}->{Content},
            );

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
    );

=cut

sub PackageApprove {
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
        SQL => 'UPDATE package_repository SET approved = version WHERE id = ?',
        Bind => [ \$Param{PackageID} ],
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
        SQL => 'UPDATE package_repository SET approved = NULL WHERE id = ?',
        Bind => [ \$Param{PackageID} ],
    );
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
