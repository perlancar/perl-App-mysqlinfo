package App::mysqlinfo;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use App::dbinfo ();

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => 'Get/extract information from MySQL database',
};

our %args_common = (
    dbname => {
        schema => 'str*',
        tags => ['connection', 'common'],
        pos => 0,
    },
    host => {
        schema => 'str*', # XXX hostname
        tags => ['connection', 'common'],
    },
    port => {
        schema => ['int*', min=>1, max=>65535], # XXX port
        tags => ['connection', 'common'],
    },
    user => {
        schema => 'str*',
        cmdline_aliases => {u=>{}},
        tags => ['connection', 'common'],
    },
    password => {
        schema => 'str*',
        cmdline_aliases => {p=>{}},
        tags => ['connection', 'common'],
        description => <<'_',

You might want to specify this parameter in a configuration file instead of
directly as command-line option.

_
    },
    dbh => {
        summary => 'Alternative to specifying dsn/user/password (from Perl)',
        schema => 'obj*',
        tags => ['connection', 'common', 'hidden-cli'],
    },
);

our %args_rels_common = (
    'req_one&' => [
        [qw/dbname dbh/],
    ],
);

our %arg_table = %App::dbinfo::arg_table;

our %arg_detail = %App::dbinfo::arg_detail;

sub __json_encode {
    state $json = do {
        require JSON::MaybeXS;
        JSON::MaybeXS->new->canonical(1);
    };
    $json->encode(shift);
}

sub _connect {
    require DBIx::Connect::MySQL;

    my $args = shift;

    return $args->{dbh} if $args->{dbh};
    DBIx::Connect::MySQL->connect(
        join(
            "",
            "DBI:mysql:database=$args->{dbname}",
            (defined $args->{host} ? ";host=$args->{host}" : ""),
            (defined $args->{port} ? ";port=$args->{port}" : ""),
        ),
        $args->{user}, $args->{password},
        {RaiseError=>1});
}

sub _preprocess_args {
    my $args = shift;

    if ($args->{dbh}) {
        return $args;
    }
    $args->{dbh} = _connect($args);
    $args->{_dbname} = delete $args->{dbname};

    if (defined $args->{table}) {
        $args->{table} = "$args->{_dbname}.$args->{table}"
            unless $args->{table} =~ /\./;
    }

    $args;
}

$SPEC{list_tables} = {
    v => 1.1,
    summary => 'List tables in the database',
    args => {
        %args_common,
    },
    args_rels => {
        %args_rels_common,
    },
};
sub list_tables {
    my %args = @_;

    _preprocess_args(\%args);
    my $res = App::dbinfo::list_tables(%args);
    if ($res->[0] == 200) {
        for (@{ $res->[2] }) { s/^\Q$args{_dbname}\E\.// }
    }
    $res;
}

$SPEC{list_columns} = {
    v => 1.1,
    summary => 'List columns of a table',
    args => {
        %args_common,
        %arg_table,
        %arg_detail,
    },
    args_rels => {
        %args_rels_common,
    },
    examples => [
        {
            args => {dbname=>'test', table=>'main.table1'},
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
};
sub list_columns {
    my %args = @_;
    _preprocess_args(\%args);
    App::dbinfo::list_columns(%args);
}

$SPEC{dump_table} = {
    v => 1.1,
    summary => 'Dump table into various formats',
    args => {
        %args_common,
        %arg_table,
        %App::dbinfo::args_dump_table,
    },
    args_rels => {
        %args_rels_common,
    },
    result => {
        schema => 'str*',
    },
    examples => [
    ],
};
sub dump_table {
    my %args = @_;
    _preprocess_args(\%args);
    App::dbinfo::dump_table(%args);
}


1;
#ABSTRACT:

=head1 SYNOPSIS

See included script L<mysqlinfo>.


=head1 SEE ALSO

L<DBI>

L<App::dbinfo>
