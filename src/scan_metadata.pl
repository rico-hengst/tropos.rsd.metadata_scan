#!/usr/bin/env perl
##################################################################
# load pmodules
use feature 'say';
use Modern::Perl;
use utf8;
use DateTime;


use File::Find::Rule;
use File::Basename;
use Encode;
use Template;

use Config::Tiny;

use FindBin;
use Path::Class;  # Exports dir() by default

use Data::Dump qw(dump);



# get config
my $config_file = $FindBin::Bin . "/../config/config.ini.private";

unless (-f $config_file) {
    say "Config file not exists $config_file";
    exit;
}

my $config1 = Config::Tiny->read( $config_file );

unless($config1) {
    say("Config $config_file is empty!");
    exit;
}


# get and check archive dirs
my @ARCHIVE_DIRS = split(/,/,$config1->{metadataconfig}->{archive_dirs});
say("No directories to scan, config???") if(@ARCHIVE_DIRS==0);
foreach my $archive_dir (@ARCHIVE_DIRS) {
    unless(-d $archive_dir) {
        say("WARN: Archive dir not exists: " . $archive_dir);
        exit;
    }
    say($archive_dir);
}
 

# define Find Rule
my $rule =  File::Find::Rule->new;
$rule->directory;
$rule->maxdepth(1);



# main
my $time1 = DateTime->now();
my ($tree_hash) = scan_tree($config1->{metadataconfig}->{maxlevel_directory_tree},\@ARCHIVE_DIRS,{},$config1);
my $time2 = DateTime->now();


#say($duration_scan_tree);

#say(dump(%$tree_hash));

my $meta_hash = scan_m(\@ARCHIVE_DIRS, $config1);
my $time3 = DateTime->now();
# merge
my $merged_hash = merge_hashes($meta_hash, $tree_hash);

#say(dump ${ $merged_hash }{"/home/hengst/Documents/russland"});
#say(dump(%$merged_hash));

# generate html
$$config1{time_consumption_directory_tree} = $time1 - $time2;
$$config1{time_consumption_metadata} = $time3 - DateTime->now();

say(dump(%$config1));

generate_html(\@ARCHIVE_DIRS, $config1, $merged_hash);


#######################
# scan directory tree
# return hash
sub scan_tree{
    my($counter, $dirs,$tree_hash, $config1) = @_;
   
    foreach my $dir (@$dirs) {
        #say($dir);
        
        # find sub_dirs
        my @sub_dirs = $rule->in( $dir );
        
        # remove first
        shift @sub_dirs;
        
        # sort
        @sub_dirs = sort { lc($a) cmp lc($b) } @sub_dirs;
        
        # get Path Class Dir
        my $pcd = Path::Class::Dir->new($dir);
        
        # get stat info
        my ($device, $inode, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks) = stat($dir);

        say("mode $mode" . sprintf "%04o", $mode & 07777);
        # add record to hash
        $$tree_hash{$dir}{parent_path} = $pcd->parent->stringify;
        $$tree_hash{$dir}{child_paths} = \@sub_dirs;
        $$tree_hash{$dir}{current_dir} = $pcd->basename;
        
        $$tree_hash{$dir}{access}      = sprintf "%04o", $mode & 07777;
        $$tree_hash{$dir}{owner}       = getpwuid $uid;      
        $$tree_hash{$dir}{group}       = getgrgid $gid;

        
        
        # test if you can enter the directory
        my $is_executable = 1;
        unless(-x $dir){
            my $is_executable = 0;
            $$tree_hash{$dir}{is_executable} = $is_executable;
            say "--------- not executable $dir";
           # last;
        }
        else {
            $$tree_hash{$dir}{is_executable} = $is_executable;
        }
        
                
        # next deep
        if($counter == 0 && $$tree_hash{$dir}{is_executable}) {
            if($config1->{metadataconfig}->{show_total_size_directory_tree}) {
                $b = $pcd->basename;
                my $du = `du -sh $dir | cut -f1`;
                $$tree_hash{$dir}{disk_usage} = $du;
            }
        }
        else {
            $tree_hash = scan_tree($counter - 1, \@sub_dirs, $tree_hash, $config1);
        }
    }
    
    return $tree_hash;
}

######################################
# scan directory tree and looking for metadata files
# return hash
sub scan_m{
    my ($archive_dirs, $config2) = @_;
    say($config2->{metadataconfig}->{metadata_filenames});
    
    # find files
    my @files = File::Find::Rule->maxdepth( $config2->{metadataconfig}->{maxlevel_metadata} )
                            ->file()
                           # ->name( 'metadata', 'METADATA', 'readme' )
                            ->name( split(",",$config2->{metadataconfig}->{metadata_filenames}) )
                            ->in( @$archive_dirs )
                            #->extras({ follow => 1 })
                            ;
                            
    # read files
    # read ini files and push to a HASH
    my %META_HASH;
    foreach my $file (@files) {
        #say $file;
        # Open the config
        my $config = Config::Tiny->read( $file );
        $META_HASH{$file} = $config;
    }
    
    return \%META_HASH;
}

##############################
# merge two hashes togeteher and include metadata to tree hash
# return hash
sub merge_hashes {
    my ($meta_hash, $tree_hash) = @_;
    
    my $merged_hash = { %$tree_hash };
    
    foreach my $key (keys %$meta_hash) {
                
        my $dirname = dirname($key);
        
        # put metadata record to merged hash
        if (${ $tree_hash }{$dirname}) {
            ${ $merged_hash }{$dirname}{metadata}{pathfilename} =  $key;
            ${ $merged_hash }{$dirname}{metadata}{filename}     =  fileparse($key);
            ${ $merged_hash }{$dirname}{metadata}{content}      =  ${ $meta_hash }{$key};

        }
    }
    
    return $merged_hash;
}


##############################
# generate html from template
sub generate_html {
    my ($archive_dirs, $config1, $hash) = @_;
    my $template_file   = $FindBin::Bin . "/template/output_template.tt";
    my $output_file     = $config1->{metadataconfig}->{output_file} ? $config1->{metadataconfig}->{output_file} : $FindBin::Bin . "/metadata.html";
    say("Generate HTML" . $output_file);

    my $tt = Template->new({
        ENCODING    => 'utf8',
        ABSOLUTE    => 1,
        });
        
    $tt->process(
        $template_file, 
        {
                content => $hash, 
                config => $config1,
                dataset_dirs => $archive_dirs,
                datetime => DateTime->now()}, 
        $output_file,
        #{binmode => ':utf8'}
    )
    or die $tt->error;
}
