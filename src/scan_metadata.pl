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

use Getopt::Long qw(GetOptions);

use Chart::Plotly::Trace::Sunburst;
use Chart::Plotly::Plot;
  



# get config
my $config_file = $FindBin::Bin . "/../config/config.ini.private";


sub usage {
    print <<EOF;
######################################################################################
Usage:       $0 ../../done_filelist/done_filelist_20190509.txt --check_image_exists yes

Description: The script processes a file (done_file_list) and update the polly database.

Options:
            -check_image_exists        (yes|no) DEFAULT: yes
######################################################################################
EOF
    exit 1;
}


GetOptions(
    "config_file=s"  => \$config_file
) or die usage() . "\n";



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
#sleep(61);
my $time2 = DateTime->now();


my $rr= $time2 - $time1;

say("minutes " . $rr->in_units('minutes') . ", seconds" . $rr->in_units('seconds'));


#say($duration_scan_tree);

#say(dump(%$tree_hash));

my $meta_hash = scan_m(\@ARCHIVE_DIRS, $config1);
my $time3 = DateTime->now();
# merge
my $merged_hash = merge_hashes($meta_hash, $tree_hash);
my $merged_hash = add_du_to_all(\@ARCHIVE_DIRS, $config1, $merged_hash);


# generate html
$$config1{time_consumption_directory_tree} = $time2 - $time1;
$$config1{time_consumption_metadata} = DateTime->now() - $time3;

say(dump(%$config1));

generate_html(\@ARCHIVE_DIRS, $config1, $merged_hash);
generate_file_size(\@ARCHIVE_DIRS, $config1, $merged_hash);

say("2-1" . dump($time2 - $time1));
say("2-1" . dump(DateTime->now() - $time3));

#######################
# scan directory tree
# return hash
sub scan_tree{
    my($counter, $dirs,$tree_hash, $config1) = @_;
    
    my @SCAN_PROHIBITED_DIRS = split(",",$config1->{metadataconfig}->{scan_prohibited_dirs});
   
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

        say(" dir: $dir");
        # add record to hash
        $$tree_hash{$dir}{parent_path}          = $pcd->parent->stringify;
        $$tree_hash{$dir}{child_paths}          = \@sub_dirs;
        $$tree_hash{$dir}{current_dir}          = $pcd->basename;
        
        $$tree_hash{$dir}{access}               = sprintf "%04o", $mode & 07777;
        $$tree_hash{$dir}{owner}                = getpwuid $uid;      
        $$tree_hash{$dir}{group}                = getgrgid $gid;
        $$tree_hash{$dir}{level_directory_tree} = $config1->{metadataconfig}->{maxlevel_directory_tree} - $counter;
        
        
        # check if enter dir is prohibited
        $$tree_hash{$dir}{is_prohibited}    = 0;
        if ( grep( /^$dir$/, @SCAN_PROHIBITED_DIRS ) ) {
            print "prohibited dir found";
            $$tree_hash{$dir}{is_prohibited}= 1;
        }
        

        
        
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
        
                
        # next deep and disk usage
        
        # disk usage
        if($counter == 0 && $config1->{metadataconfig}->{show_total_size_directory_tree}) {
            $b = $pcd->basename;
            # du in GB
            my $du = `du -s $dir | cut -f1 | awk '{print \$1 /1024/1024}' | awk '{printf "\%4.2f", \$1}'`;
            #my $du = `du -s $dir | cut -f1 | awk '{print \$1 /1024}' | awk '{printf "\%4.2f", \$1}'`;
            #say("disk usage: $du");
 
            $$tree_hash{$dir}{disk_usage} = $du;
        }
        
        
        if($counter > 0 && $$tree_hash{$dir}{is_executable} && $$tree_hash{$dir}{is_prohibited} == 0) {
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
# compute disk_usage to upper dirs
sub add_du_to_all {
    my ($archive_dirs, $config1, $hash) = @_;
    
    foreach my $archive_dir (@$archive_dirs) {
    }
    
    
    my $icount = $config1->{metadataconfig}->{maxlevel_directory_tree};
    while ($icount > 0)
    {
        foreach my $dir (keys $hash) {
            #say "dir: " . $dir;
            if($$hash{$dir}{level_directory_tree} == $icount) {
                my $parent_path = $$hash{$dir}{parent_path};
                
                unless ($$hash{$dir}{disk_usage}) {
                    $$hash{$dir}{disk_usage} = 0;
                }
                if (exists($$hash{$parent_path}{disk_usage})){
                    #say $dir ." 1  " . $$hash{$dir}{disk_usage};
                    $$hash{$parent_path}{disk_usage} = $$hash{$parent_path}{disk_usage} + 0 + $$hash{$dir}{disk_usage} + 0;
                    #say $dir ." 2  " . $$hash{$dir}{disk_usage};
                }
                else {
                    $$hash{$parent_path}{disk_usage} = $$hash{$dir}{disk_usage} + 0;
                }
            }
        }

        $icount--;
    }
    #print dump($hash);
    return $hash;
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

##############################
# generate txt from template
sub generate_file_size {
    my ($archive_dirs, $config1, $hash) = @_;
    
    my $template_file   = $FindBin::Bin . "/template/file_size_template.tt";

    foreach my $archive_dir (@$archive_dirs) {
        
        my $rootalias = "";
        my @parts = split('/', $archive_dir);
        if( @parts > 1 ) {
            $rootalias = $parts[@parts - 2];
        } else {
            $rootalias = '/';
        }
                
        
        
        my $output_file     = $config1->{metadataconfig}->{output_file_file_size} ? $config1->{metadataconfig}->{output_file} : $FindBin::Bin . "/" . $rootalias . "_file_size.txt";
        say("Generate TXT" . $output_file);

        my $tt = Template->new({
            ENCODING    => 'utf8',
            ABSOLUTE    => 1
            });
            
        $tt->process(
            $template_file, 
            {
                    content => $hash, 
                    config => $config1,
                    dataset_dirs => [$archive_dir],
                    rootalias => $rootalias,
                    datetime => DateTime->now()}, 
            $output_file,
            #{binmode => ':utf8'}
        )
        or die $tt->error;
    }

}



#my $trace1 = Chart::Plotly::Trace::Sunburst->new(
      #"labels"=>["Eve", "Cain", "Seth", "Enos", "Noam", "Abel", "Awan", "Enoch", "Azura"],
      #"parents"=>["", "Eve", "Eve", "Seth", "Seth", "Eve", "Eve", "Awan", "Eve" ],
      #"domain"=>{"x"=>[0, 0.5]}
  #);
  
#my $trace2 = Chart::Plotly::Trace::Sunburst->new(
      #"labels"=>["Cain", "Seth", "Enos", "Noam", "Abel", "Awan", "Enoch", "Azura"],
      #"parents"=>["Eve", "Eve", "Seth", "Seth", "Eve", "Eve", "Awan", "Eve" ],
      #"domain"=>{"x"=>[0.5, 1]}
  #);
  
#my $plot = Chart::Plotly::Plot->new(
    #traces => [ $trace1, $trace2 ],
#);

#Chart::Plotly::render_full_html($trace1);
  
