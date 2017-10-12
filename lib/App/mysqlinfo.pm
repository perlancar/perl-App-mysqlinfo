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

my %args_common = (
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
    user     => $App::dbinfo::args_common{user},
    password => $App::dbinfo::args_common{password},
    dbh      => $App::dbinfo::args_common{dbh},
);

my %args_rels_common = (
    'req_one&' => [
        [qw/dbname dbh/],
    ],
);

sub __json_encode {
    state $json = do {
        require JSON::MaybeXS;
        JSON::MaybeXS->new->canonical(1);
    };
    $json->encode(shift);
}

sub _connect {
    require DBI;

    my $args = shift;

    return $args->{dbh} if $args->{dbh};
    DBI->connect(
        join(
            "",
            "DBI:mysql:database=$args->{dbname}",
            (defined $args->{host} ? ";host=$args{host}" : ""),
            (defined $args->{port} ? ";port=$args{port}" : ""),

        $args->{user}, $args->{password},
        {RaiseError=>1});
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
    require DBIx::Diff::Schema;

    my %args = @_;

    my $dbh = _connect(\%args);

    return [200, "OK", [
            DBIx::Diff::Schema::_list_tables($dbh)]];
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
            args => {dsn=>'dbi:SQLite:database=/tmp/test.db', table=>'main.table1'},
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
};
sub list_columns {
    require DBIx::Diff::Schema;

    my %args = @_;

    my $dbh = _connect(\%args);

    my $ltres = list_tables(%args);
    return [500, "Can't list tables: $ltres->[0] - $ltres->[1]"]
        unless $ltres->[0] == 200;
    my $tables = $ltres->[2];
    #my $tables_wo_schema = [map {my $n=$_; $n=~s/.+\.//; $n} @$tables];
    #return [404, "No such table '$args{table}'"]
    #    unless grep { $args{table} eq $_ } (@$tables, @$tables_wo_schema);
    return [404, "No such table '$args{table}'"]
        unless grep { $args{table} eq $_ } @$tables;

    my @cols = DBIx::Diff::Schema::_list_columns($dbh, $args{table});
    @cols = map { $_->{COLUMN_NAME} } @cols unless $args{detail};
    return [200, "OK", \@cols];
}

$SPEC{dump_table} = {
    v => 1.1,
    summary => 'Dump table into various formats',
    args => {
        %args_common,
        %arg_table,
        row_format => {
            schema => ['str*', in=>['array', 'hash']],
            default => 'hash',
            cmdline_aliases => {
                array => { summary => 'Shortcut for --row-format=array', is_flag=>1, code => sub { $_[0]{row_format} = 'array' } },
                a     => { summary => 'Shortcut for --row-format=array', is_flag=>1, code => sub { $_[0]{row_format} = 'array' } },
            },
        },
        exclude_columns => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'exclude_column',
            schema => ['array*', {
                of=>'str*',
                #'x.perl.coerce_rules'=>['str_comma_sep'],
            }],
            cmdline_aliases => {C=>{}},
        },
        include_columns => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'include_column',
            schema => ['array*', {
                of=>'str*',
                #'x.perl.coerce_rules'=>['str_comma_sep'],
            }],
            cmdline_aliases => {c=>{}},
        },
        wheres => {
            summary => 'Add WHERE clause',
            'x.name.is_plural' => 1,
            'x.name.singular' => 'where',
            schema => ['array*', {
                of=>'str*',
            }],
            cmdline_aliases => {w=>{}},
        },
        limit_number => {
            schema => 'nonnegint*',
            cmdline_aliases => {n=>{}},
        },
        limit_offset => {
            schema => 'nonnegint*',
            cmdline_aliases => {o=>{}},
        },
    },
    args_rels => {
        %args_rels_common,
    },
    result => {
        schema => 'str*',
    },
    examples => [
        {
            argv => [qw/table1/],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Only include specified columns',
            argv => [qw/table2 -c col1 -c col2/],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Exclude some columns',
            argv => [qw/table3 -C col1 -C col2/],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Select some rows',
            argv => ['table4', '-w', q(name LIKE 'John*'), '-n', 10],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
};
sub dump_table {
    require DBIx::Diff::Schema;

    my %args = @_;
    my $table = $args{table};
    my $is_hash = $args{row_format} eq 'array' ? 0:1;

    # let's ignore schema for now
    $table =~ s/.+\.//;

    $is_hash++ if $args{exclude_columns} && @{$args{exclude_columns}};

    my $col_term = "*";
    if ($args{include_columns} && @{$args{include_columns}}) {
        $col_term = join(",", map {qq("$_")} @{$args{include_columns}});
    }

    my $dbh = _connect(\%args);

    my $wheres = $args{wheres};
    my $sql = join(
        "",
        "SELECT $col_term FROM \"$table\"",
        ($args{wheres} && @{$args{wheres}} ?
             " WHERE ".join(" AND ", @{$args{wheres}}) : ""),
        # XXX what about database that don't support LIMIT clause?
        (defined $args{limit_offset} ? " LIMIT $args{limit_offset},".($args{limit_number} // "-1") :
             defined $args{limit_number} ? " LIMIT $args{limit_number}" : ""),
    );

    my $sth = $dbh->prepare($sql);
    $sth->execute;

    my $code_get_row = sub {
        my $row;
        if ($is_hash) {
            $row = $sth->fetchrow_hashref;
            return undef unless $row;
            if ($args{exclude_columns} && @{$args{exclude_columns}}) {
                for (@{ $args{exclude_columns} }) {
                    delete $row->{$_};
                }
            }
        } else {
            $row = $sth->fetchrow_arrayref;
            return undef unless $row;
        }
        __json_encode($row);
    };

    [200, "OK", $code_get_row, {stream=>1}];
}


1;
#ABSTRACT:

=head1 SYNOPSIS

See included script L<dbinfo>.


=head1 SEE ALSO

L<DBI>

L<App::diffdb>
