#!/usr/bin/perl
###########################################################################
# ABI-compliance-checker v1.1, lightweight tool for checking
# backward/forward binary compatibility of shared C/C++ libraries in OS Linux.
# Copyright (C) The Linux Foundation
# Copyright (C) Institute for System Programming, RAS
# Author: Andrey Ponomarenko <andrei.moscow@mail.ru>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
###########################################################################

use Getopt::Long;
Getopt::Long::Configure ("posix_default", "no_ignore_case");

my ($Help, %Descriptor, $TargetLibraryName, $AllInOneHeader, $GenDescriptor, $TestSystem);

GetOptions("help|h!" => \$Help,
 "l=s" => \$TargetLibraryName,
 "d1=s" => \$Descriptor{1}{'Path'},
 "d2=s" => \$Descriptor{2}{'Path'},
 "test!" => \$TestSystem,
 "d!" => \$GenDescriptor,
 "fast!" => \$AllInOneHeader);

sub HELP_MESSAGE()
{
    print STDERR <<"EOM"

Name:
  $0: lightweight tool for checking backward/forward binary compatibility of shared C/C++ libraries in OS Linux, it checks interface signatures and data type definitions in two library versions (headers and shared objects) and searches ABI changes that may lead to incompatibility.

Usage:
  $0 [options] 

Options:
  -help            This help message.
  -l  <name>       Library name.
  -d1 <path>       Path to descriptor of 1st library version (see descriptor format below).
  -d2 <path>       Path to descriptor of 2nd library version.
  -d               Generate the library descriptor templates lib_descriptor.v1 and lib_descriptor.v2
  -fast            Compiling of all headers together (It is very fast but possible compiler errors in one header may affect others).

Examples:
  $0 -l glib -d1 descriptor_glib_2.20.3 -d2 descriptor_glib_2.20.4
  $0 -l gtk2 -d1 descriptor_gtk2_2.16.4 -d2 descriptor_gtk2_2.17.3

Library descriptor format:

<version>
    /* Library version */
</version>

<headers>
    /* The list of header paths or directories, one per line */
</headers>

<libs>
    /* The list of shared object paths or directories, one per line */
</libs>

<include_paths>
    /* The list of directories to be searched for header files needed for compiling of library headers, one per line */
    /* This section is not necessary */
</include_paths>

<gcc_options>
    /* Addition gcc options, one per line */
    /* This section is not necessary */
</gcc_options>

<opaque_types>
    /* The list of types that should be skipped while checking, one per line */
    /* This section is not necessary */
</opaque_types>

<internal_functions>
    /* The list of functions that should be skipped while checking, one mangled name per line */
    /* This section is not necessary */
</internal_functions>

<include_preamble>
    /* The list of headers that will be included before each analyzed header */
    /* For example, it is a tree.h for libxml2 and ft2build.h for freetype2 */
    /* This section is not necessary */
    /* This section is useless when -fast option selected */
</include_preamble>

Library descriptor example:

<version>
    2.26.0
</version>

<headers>
   /usr/local/librsvg/librsvg-2.26.0/include
</headers>

<libs>
   /usr/local/librsvg/librsvg-2.26.0/lib
</libs>

<include_paths>
   /usr/include/glib-2.0
   /usr/include/gtk-2.0
   /usr/include/atk-1.0
   /usr/include/cairo
   /usr/include/pango-1.0
   /usr/include/pixman-1
   /usr/include/freetype2
   /usr/include/libpng12
</include_paths>

Report bugs to <abi.compliance.checker\@gmail.com>.
For more information, please see: http://ispras.linux-foundation.org/index.php/ABI_compliance_checker.
EOM
      ;
      exit(1);
}

my %Operator_Indication = (
"not" => "~",
"assign" => "=",
"andassign" => "&=",
"orassign" => "|=",
"xorassign" => "^=",
"or" => "|",
"xor" => "^",
"and" => "&",
"lnot" => "!",
"eq" => "==",
"ne" => "!=",
"lt" => "<",
"lshift" => "<<",
"lshiftassign" => "<<=",
"rshiftassign" => ">>=",
"call" => "()",
"addr" => "&",
"mod" => "%",
"modassign" => "%=",
"subs" => "[]",
"land" => "&&",
"lor" => "||",
"rshift" => ">>",
"ref" => "->",
"le" => "<=",
"deref" => "*",
"mult" => "*",
"preinc" => "++",
"delete" => " delete",
"vecnew" => " new[]",
"vecdelete" => " delete[]",
"predec" => "--",
"postinc" => "++",
"postdec" => "--",
"plusassign" => "+=",
"plus" => "+",
"minus" => "-",
"minusassign" => "-=",
"gt" => ">",
"ge" => ">=",
"new" => " new",
"multassign" => "*=",
"divassign" => "/=",
"div" => "/",
"neg" => "-",
"pos" => "+"
);

sub num_to_str($)
{
    my $Number = $_[0];
    if(int($Number)>3)
    {
        return $Number."th";
    }
    elsif(int($Number)==1)
    {
        return "1st";
    }
    elsif(int($Number)==2)
    {
        return "2nd";
    }
    elsif(int($Number)==3)
    {
        return "3rd";
    }
    else
    {
        return "";
    }
}

sub dprint($)
{
    print "\n".$_[0]."\n";
}

#GLOBAL VARIABLES
my $REPORT_PATH;
my %Cache;
my %FuncAttr;
my %LibInfo;
my %HeaderCompileError;
my $StartTime;
my $WARNINGS;
my %CompilerOptions;
my $ProcessedHeader;
my %HeaderDirs;
my %Dictionary_TypeName;
my %AddedInt;
my %WithdrawnInt;
my $PointerSize;

#TYPES
my %TypeDescr;
my %OpaqueTypes;

#FUNCTIONS
my %FuncDescr;
my %ClassFunc;
my %ClassVirtFunc;
my %ClassIdVirtFunc;
my %ClassId;
my %tr_name;
my %mangled_name;
my %InternalInterfaces;

my %TargetInterfaces;
my %TargetTypes;
my %InsertedInterfaces;

#HEADERS
my %HeaderDestination;
my %DestinationHeader;
my %Include_Preamble;

#MERGING
my %Functions;
my @RecurTypes;
my %ReportedInterfaces;
my %LibInt;
my %LibInt_Short;
my %Lib_Language;
my %Library;
my $Version;

#PROBLEM DESCRIPTIONS
my %CompatProblems;

#REPORTS
my $ContentID = 1;

sub readDescriptor($)
{
    my $LibVersion = $_[0];
    if(not -e $Descriptor{$LibVersion}{'Path'})
    {
        print "descriptor d$LibVersion does not exists, incorrect file path $Descriptor{$LibVersion}{'Path'}\n";
        exit(0);
    }
    my $Descriptor_File = `cat $Descriptor{$LibVersion}{'Path'}`;
    $Descriptor_File =~ s|/\*[^*]*\*/||igs;
    if(not $Descriptor_File)
    {
        print "descriptor d$LibVersion is empty\n";
        exit(0);
    }
    $Descriptor{$LibVersion}{'Dir'} = get_Dir_ByPath($Descriptor{$LibVersion}{'Path'});
    if($Descriptor_File =~ m/<version>[ \n]*(.*?)[ \n]*<\/version>/ios)
    {
        $Descriptor{$LibVersion}{'Version'} = $1;
    }
    else
    {
        print "select version in descriptor d$LibVersion\n";
        exit(0);
    }
    if($Descriptor_File =~ m/<headers>[ \n]*(.*?)[ \n]*<\/headers>/ios)
    {
        $Descriptor{$LibVersion}{'Headers'} = $1;
    }
    else
    {
        print "select headers in descriptor d$LibVersion\n";
        exit(0);
    }
    if($Descriptor_File =~ m/<libs>[ \n]*(.*?)[ \n]*<\/libs>/ios)
    {
        $Descriptor{$LibVersion}{'Libs'} = $1;
    }
    else
    {
        print "select libs in descriptor d$LibVersion\n";
        exit(0);
    }
    if($Descriptor_File =~ m/<include_paths>[ \n]*(.*?)[ \n]*<\/include_paths>/ios)
    {
        $Descriptor{$LibVersion}{'Include_Paths'} = $1;
    }
    if($Descriptor_File =~ m/<gcc_options>[ \n]*(.*?)[ \n]*<\/gcc_options>/ios)
    {
        $Descriptor{$LibVersion}{'Gcc_Options'} = $1;
        foreach my $Option (split("\n", $Descriptor{$LibVersion}{'Gcc_Options'}))
        {
            $Option =~ s/\A[ ]*//g;
            $Option =~ s/[ ]*\Z//g;
            $CompilerOptions{$LibVersion} .= " ".$Option;
        }
    }
    if($Descriptor_File =~ m/<opaque_types>[ \n]*(.*?)[ \n]*<\/opaque_types>/ios)
    {
        $Descriptor{$LibVersion}{'Opaque_Types'} = $1;
        foreach my $Type_Name (split("\n", $Descriptor{$LibVersion}{'Opaque_Types'}))
        {
            $Type_Name =~ s/\A[ ]*//g;
            $Type_Name =~ s/[ ]*\Z//g;
            $OpaqueTypes{$Type_Name} = 1;
        }
    }
    if($Descriptor_File =~ m/<internal_functions>[ \n]*(.*?)[ \n]*<\/internal_functions>/ios)
    {
        $Descriptor{$LibVersion}{'Internal_Functions'} = $1;
        foreach my $Interface_Name (split("\n", $Descriptor{$LibVersion}{'Internal_Functions'}))
        {
            $Interface_Name =~ s/\A[ ]*//g;
            $Interface_Name =~ s/[ ]*\Z//g;
            $InternalInterfaces{$Interface_Name} = 1;
        }
    }
    if($Descriptor_File =~ m/<include_preamble>[ \n]*(.*?)[ \n]*<\/include_preamble>/ios)
    {
        $Descriptor{$LibVersion}{'Include_Preamble'} = $1;
        foreach my $Header_Name (split("\n", $Descriptor{$LibVersion}{'Include_Preamble'}))
        {
            $Header_Name =~ s/\A[ ]*//g;
            $Header_Name =~ s/[ ]*\Z//g;
            $Include_Preamble{$Header_Name} = 1;
        }
    }
}

sub getInfo($)
{
	my $FileDest = $_[0];
	my @FileContent;
	my $LineNum = 0;
	my $SubLineNum;
	my $InfoLine;
	my $InfoId;
	my $NextInfoLine;
	@FileContent = split("\n", `cat $FileDest`);
	while($LineNum <= $#FileContent)
	{
		$InfoLine = $FileContent[$LineNum];
		chomp($InfoLine);
		next if($InfoLine !~ /\A@([0-9]+)/);
		$InfoId = $1;
		if($InfoId)
		{
			$SubLineNum = 1;
			while(($LineNum + $SubLineNum <= $#FileContent) and (not $FileContent[$LineNum + $SubLineNum] =~ m/\A\@/))
			{
				$NextInfoLine = $FileContent[$LineNum + $SubLineNum];
				chomp($NextInfoLine);
				$InfoLine .= " ".$NextInfoLine;
				$SubLineNum += 1;
			}
			$LineNum += $SubLineNum - 1;
		}
		$InfoLine =~ s/ [ ]+/  /g;
		$LineNum += 1;
		next if($InfoLine !~ /\A@([0-9]+)[ ]+([a-zA-Z_]+)[ ]+(.*)\Z/);
        next if($2 =~ /_expr|statement_list|_stmt/);
		$LibInfo{$Version}{$1}{'info_type'}=$2;
		$LibInfo{$Version}{$1}{'info'}=$3;
	}
	#ANALIZE TYPES INFO
	getTypeDescr_All();
	getDerivedTypeDescr_All();
    getDerivedTypeDescr_All();
	#ANALIZE FUNCS INFO
	getFuncDescr_All();
	
	#ANALIZE VARIABLES INFO
	getVarDescr_All();
}

sub getTypeDeclId($)
{
	my $TypeInfo = $LibInfo{$Version}{$_[0]}{'info'};
	if($TypeInfo =~ /name[ ]*:[ ]*@([0-9]+)/)
    {
        return $1;
    }
    else
    {
        return "";
    }
}

sub getTypeDeclId_by_Ver($$)
{
	my $LibVersion = $_[1];
	my $TypeInfo = $LibInfo{$LibVersion}{$_[0]}{'info'};
	if($TypeInfo =~ /name[ ]*:[ ]*@([0-9]+)/)
    {
	    return $1;
    }
    else
    {
        return "";
    }
}

sub isFuncPtr($)
{
    my $Ptd = pointTo($_[0]);
	if($Ptd)
	{
		if(($LibInfo{$Version}{$_[0]}{'info'} =~ m/unql[ ]*:/) and not ($LibInfo{$Version}{$_[0]}{'info'} =~ m/qual[ ]*:/))
		{
			return 0;
		}
		elsif(($LibInfo{$Version}{$_[0]}{'info_type'} eq "pointer_type") and ($LibInfo{$Version}{$Ptd}{'info_type'} eq "function_type"))
		{
			return 1;
		}
		else
		{
			return 0;
		}
	}
	else
	{
		return 0;
	}
}

sub pointTo($)
{
	my $TypeInfo = $LibInfo{$Version}{$_[0]}{'info'};
	if($TypeInfo =~ /ptd[ ]*:[ ]*@([0-9]+)/)
    {
	    return $1;
    }
    else
    {
        return "";
    }
}

sub getTypeDescr_All()
{
	foreach (keys(%{$LibInfo{$Version}}))
	{
		if($LibInfo{$Version}{$_}{'info_type'} eq "type_decl")
		{
			getTypeDescr($_);
		}
	}
}

my %AllowedDerivedType=(
    "pointer_type"=>1,
    "reference_type"=>1,
    "array_type"=>1,
    "integer_type"=>1,
    "enumeral_type"=>1,
    "record_type"=>1,
    "real_type"=>1,
    "complex_type"=>1,
    "void_type"=>1,
    "boolean_type"=>1  );

sub getDerivedTypeDescr_All()
{
	foreach (keys(%{$LibInfo{$Version}}))
	{
        my $TypeType = $LibInfo{$Version}{$_}{'info_type'};
		if($TypeType =~ /_type\Z/ and ($TypeType ne "function_type") and ($TypeType ne "method_type") and ($TypeType ne "lang_type"))#$AllowedDerivedType{$TypeType}
		{
			getDerivedTypeDescr($_);
		}
	}
}

sub getDerivedTypeDescr($)
{
	my $TypeId = $_[0];
	my $TypeDeclId = getTypeDeclId($TypeId);
	%{$TypeDescr{$Version}{$TypeDeclId}{$TypeId}} = getDerivedTypeAttr($TypeDeclId, $TypeId);
    $Dictionary_TypeName{$TypeDescr{$Version}{$TypeDeclId}{$TypeId}{'Name'}} = 1;
}

sub getDerivedTypeAttr($$)
{
    my $TypeDeclId = $_[0];
    my $TypeId = $_[1];
    my $BaseTypeSpec;
    my $BaseTypeType;
    my $ArrayElemNum;
    my %TypeAttr;
    my %BaseTypeAttr;
    
    $TypeAttr{'Tid'} = $TypeId;
    $TypeAttr{'TDid'} = $TypeDeclId;
    $TypeAttr{'Type'} = getTypeType($TypeDeclId, $TypeId);
    if($TypeAttr{'Type'} eq "Unknown")
    {
        return ();
    }
    if($TypeAttr{'Type'} eq "FuncPtr")
    {
        $TypeAttr{'Name'} = getFuncPtrCorrectName(pointTo($TypeId), $TypeDeclId, $TypeId);
        $TypeAttr{'Size'} = 4;
        %{$TypeDescr{$Version}{$TypeDeclId}{$TypeId}} = %TypeAttr;
        return %TypeAttr;
    }
    elsif($TypeAttr{'Type'} eq "Array")
    {
        ($TypeAttr{'BaseType'}{'Tid'}, $TypeAttr{'BaseType'}{'TDid'}, $BaseTypeSpec) = getBaseType($TypeDeclId, $TypeId);
        %BaseTypeAttr = getDerivedTypeAttr($TypeAttr{'BaseType'}{'TDid'}, $TypeAttr{'BaseType'}{'Tid'});
        $ArrayElemNum = getSize($TypeId)/8;
        $ArrayElemNum = $ArrayElemNum/$BaseTypeAttr{'Size'} if($BaseTypeAttr{'Size'});
        $TypeAttr{'Size'} = $ArrayElemNum;
        if($ArrayElemNum)
        {
            $TypeAttr{'Name'} = $BaseTypeAttr{'Name'}."[".$ArrayElemNum."]";
        }
        else
        {
            $TypeAttr{'Name'} = $BaseTypeAttr{'Name'}."[]";
        }
        $TypeAttr{'Name'} = correctName($TypeAttr{'Name'});
        $TypeAttr{'Library'} = $BaseTypeAttr{'Library'};
        $TypeAttr{'Header'} = $BaseTypeAttr{'Header'};
        $TypeAttr{'Built-In'} = $BaseTypeAttr{'Built-In'};
        %{$TypeDescr{$Version}{$TypeDeclId}{$TypeId}} = %TypeAttr;
        return %TypeAttr;
    }
    else
    {
        if($TypeDescr{$Version}{$TypeDeclId}{$TypeId}{'Name'})
        {
            return %{$TypeDescr{$Version}{$TypeDeclId}{$TypeId}};
        }
        ($TypeAttr{'BaseType'}{'Tid'}, $TypeAttr{'BaseType'}{'TDid'}, $BaseTypeSpec) = getBaseType($TypeDeclId, $TypeId);
        %BaseTypeAttr = getDerivedTypeAttr($TypeAttr{'BaseType'}{'TDid'}, $TypeAttr{'BaseType'}{'Tid'});
        if($BaseTypeAttr{'Name'} and $BaseTypeSpec)
        {
            $TypeAttr{'Name'} = $BaseTypeAttr{'Name'}." ".$BaseTypeSpec;
        }
        elsif($BaseTypeAttr{'Name'})
        {
            $TypeAttr{'Name'} = $BaseTypeAttr{'Name'};
        }
        if(not $TypeAttr{'Size'})
        {
            if($TypeAttr{'Type'} eq "Pointer")
            {
                $TypeAttr{'Size'} = $PointerSize;
            }
            else
            {
                $TypeAttr{'Size'} = $BaseTypeAttr{'Size'};
            }
        }
        $TypeAttr{'Name'} = correctName($TypeAttr{'Name'});
        $TypeAttr{'Library'} = $BaseTypeAttr{'Library'};
        $TypeAttr{'Header'} = $BaseTypeAttr{'Header'};
        $TypeAttr{'Built-In'} = $BaseTypeAttr{'Built-In'};
        %{$TypeDescr{$Version}{$TypeDeclId}{$TypeId}} = %TypeAttr;
        return %TypeAttr;
    }
}

sub getFuncPtrCorrectName($$$)
{
	my $FuncInfo = $LibInfo{$Version}{$_[0]}{'info'};
	my $ReturnTypeId;
    my $ParamTypeId;
	my $ParamTypeInfoId;
	my $ParamTypeInfo;
	my $NextParamTypeInfoId;
	my $FuncPtrCorrectName = "";
	my $TypeDeclId = $_[1];
	my $TypeId = $_[2];
	my $Position = 0;
	my @ParamTypeName;
	if($FuncInfo =~ /retn[ ]*:[ ]*@([0-9]+) /)
    {
        $ReturnTypeId = $1;
	    $FuncPtrCorrectName .= $TypeDescr{$Version}{getTypeDeclId($ReturnTypeId)}{$ReturnTypeId}{'Name'};
    }
	return $FuncPtrCorrectName."()" if($FuncInfo !~ /prms[ ]*:[ ]*@([0-9]+) /);
    $ParamTypeInfoId = $1;
	while($ParamTypeInfoId)
	{
		$ParamTypeInfo = $LibInfo{$Version}{$ParamTypeInfoId}{'info'};
		last if($ParamTypeInfo !~ /valu[ ]*:[ ]*@([0-9]+) /);
        $ParamTypeId = $1;
		last if($TypeDescr{$Version}{getTypeDeclId($ParamTypeId)}{$ParamTypeId}{'Name'} eq "void");
		$TypeDescr{$Version}{$TypeDeclId}{$TypeId}{'Memb'}{$Position}{'type'} = $ParamTypeId;
		push(@ParamTypeName, $TypeDescr{$Version}{getTypeDeclId($ParamTypeId)}{$ParamTypeId}{'Name'});
        last if($ParamTypeInfo !~ /chan[ ]*:[ ]*@([0-9]+) /);
		$ParamTypeInfoId = $1;
		$Position += 1;
	}
	$FuncPtrCorrectName .= " (*) (".join(", ", @ParamTypeName).")";
	$TypeDescr{$Version}{$TypeDeclId}{$TypeId}{'BaseType'}{'Tid'} = $ReturnTypeId;
	$TypeDescr{$Version}{$TypeDeclId}{$TypeId}{'BaseType'}{'TDid'} = getTypeDeclId($ReturnTypeId);
	return $FuncPtrCorrectName;
}

sub getTypeName($)
{
	my $Info = $LibInfo{$Version}{$_[0]}{'info'};
	if($Info =~ /name[ ]*:[ ]*@([0-9]+) /)
	{
		return getTypeNameByInfo($1);
	}
	else
	{
		if($LibInfo{$Version}{$_[0]}{'info_type'} eq "integer_type")
		{
			if($LibInfo{$Version}{$_[0]}{'info'} =~ /unsigned/)
			{
				return "unsigned int";
			}
			else
			{
				return "int";
			}
		}
		else
		{
			return "";
		}
	}
}

sub getBaseType($$)
{
	my $TypeId = $_[1];
	my $TypeDeclId = $_[0];
	my $TypeInfo = $LibInfo{$Version}{$TypeId}{'info'};
	my $BaseTypeDeclId;
    my $Type_Type = getTypeType($TypeDeclId, $TypeId);
	#qualifications
	if(($LibInfo{$Version}{$TypeId}{'info'} =~ m/qual[ ]*:[ ]*c /) and ($LibInfo{$Version}{$TypeId}{'info'} =~ m/unql[ ]*:[ ]*\@/))
	{
		if($LibInfo{$Version}{$TypeId}{'info'} =~ /unql[ ]*:[ ]*\@([0-9]+) /)
        {
		    return ($1, getTypeDeclId($1), "const");
        }
        else
        {
            return (0, 0, "");
        }
	}
	elsif(($LibInfo{$Version}{$TypeId}{'info'} =~ m/qual[ ]*:[ ]*r /) and ($LibInfo{$Version}{$TypeId}{'info'} =~ m/unql[ ]*:[ ]*\@/))
	{
		if($LibInfo{$Version}{$TypeId}{'info'} =~ /unql[ ]*:[ ]*\@([0-9]+) /)
        {
		    return ($1, getTypeDeclId($1), "restrict");
        }
        else
        {
            return (0, 0, "");
        }
	}
	elsif(($LibInfo{$Version}{$TypeId}{'info'} =~ m/qual[ ]*:[ ]*v /) and ($LibInfo{$Version}{$TypeId}{'info'} =~ m/unql[ ]*:[ ]*\@/))
	{
		if($LibInfo{$Version}{$TypeId}{'info'} =~ /unql[ ]*:[ ]*\@([0-9]+) /)
        {
		    return ($1, getTypeDeclId($1), "volatile");
        }
        else
        {
            return (0, 0, "");
        }
	}
	elsif((not ($LibInfo{$Version}{$TypeId}{'info'} =~ m/qual[ ]*:/)) and ($LibInfo{$Version}{$TypeId}{'info'} =~ m/unql[ ]*:[ ]*\@/))
	{#TYPEDEFS
		if($LibInfo{$Version}{$TypeId}{'info'} =~ /unql[ ]*:[ ]*\@([0-9]+) /)
        {
		    return ($1, getTypeDeclId($1), "");
        }
        else
        {
            return (0, 0, "");
        }
	}
	elsif($LibInfo{$Version}{$TypeId}{'info_type'} eq "reference_type")
	{
		if($TypeInfo =~ /refd[ ]*:[ ]*@([0-9]+) /)
        {
		    return ($1, getTypeDeclId($1), "&");
        }
        else
        {
            return (0, 0, "");
        }
	}
	elsif($LibInfo{$Version}{$TypeId}{'info_type'} eq "array_type")
	{
		if($TypeInfo =~ /elts[ ]*:[ ]*@([0-9]+) /)
        {
		    return ($1, getTypeDeclId($1), "");
        }
        else
        {
            return (0, 0, "");
        }
	}
	elsif($LibInfo{$Version}{$TypeId}{'info_type'} eq "pointer_type")
	{
		if($TypeInfo =~ /ptd[ ]*:[ ]*@([0-9]+) /)
        {
		    return ($1, getTypeDeclId($1), "*");
        }
        else
        {
            return (0, 0, "");
        }
	}
	elsif(isAnonTypedef($TypeId))
	{
		$BaseTypeDeclId = anonTypedef($TypeId);
		if(($TypeDeclId eq $BaseTypeDeclId) and ($TypeId eq getTypeId($BaseTypeDeclId)))
		{
			return (0, 0, "");
		}
		else
		{
			return (getTypeId($BaseTypeDeclId), $BaseTypeDeclId, "");
		}
	}
	else
	{
		return (0, 0, "");
	}
}

sub getFuncDescr_All()
{
	foreach (keys(%{$LibInfo{$Version}}))
	{
		if($LibInfo{$Version}{$_}{'info_type'} eq "function_decl")
		{
			getFuncDescr($_);
		}
	}
}

sub getVarDescr_All()
{
	foreach (keys(%{$LibInfo{$Version}}))
	{
		if($LibInfo{$Version}{$_}{'info_type'} eq "var_decl")
		{
			getVarDescr($_);
		}
	}
}

sub getVarDescr($)
{
	my $FuncInfoId = $_[0];
	my $FuncId;
	my $FuncKind;
    ($FuncDescr{$Version}{$FuncInfoId}{'Header'}, $FuncDescr{$Version}{$FuncInfoId}{'Line'}) = getFuncHeader($FuncInfoId);
    $FuncDescr{$Version}{$FuncInfoId}{'ShortName'} = getTypeNameByInfo($FuncInfoId);
    $FuncDescr{$Version}{$FuncInfoId}{'MnglName'} = getFuncMnglName($FuncInfoId);
    if(not $FuncDescr{$Version}{$FuncInfoId}{'MnglName'})
    {
        $FuncDescr{$Version}{$FuncInfoId}{'Name'} = $FuncDescr{$Version}{$FuncInfoId}{'ShortName'};
        $FuncDescr{$Version}{$FuncInfoId}{'MnglName'} = $FuncDescr{$Version}{$FuncInfoId}{'ShortName'};
    }
    if(defined $LibInt{$Version}{$FuncDescr{$Version}{$FuncInfoId}{'MnglName'}})
    {
        $FuncDescr{$Version}{$FuncInfoId}{'SrcBin'} = "Both";
        $FuncDescr{$Version}{$FuncInfoId}{'Library'} = $TargetLibraryName;
    }
    else
    {
        delete $FuncDescr{$Version}{$FuncInfoId};
        return;
    }
	$FuncDescr{$Version}{$FuncInfoId}{'Return'} = getTypeId($FuncInfoId);
	$FuncDescr{$Version}{$FuncInfoId}{'Type'} = "Data";
	$FuncDescr{$Version}{$FuncInfoId}{'Kind'} = "Normal";
	$FuncDescr{$Version}{$FuncInfoId}{'Class'} = getFuncClass($FuncInfoId);
	$FuncDescr{$Version}{$FuncInfoId}{'NameSpace'} = getNameSpace($FuncInfoId);
	
	if(($FuncDescr{$Version}{$FuncInfoId}{'Header'} eq "<built-in>") or ($FuncDescr{$Version}{$FuncInfoId}{'Header'} eq "<internal>"))
	{
		$FuncDescr{$Version}{$FuncInfoId}{'Built-In'} = 1;
		$FuncDescr{$Version}{$FuncInfoId}{'SrcBin'} = "BinOnly";
        $FuncDescr{$Version}{$FuncInfoId}{'Header'} = "";
	}
	else
	{
		$FuncDescr{$Version}{$FuncInfoId}{'SrcBin'} = "Both";
	}
	$FuncDescr{$Version}{$FuncInfoId}{'Access'} = getFuncAccess($FuncInfoId);
	if($FuncDescr{$Version}{$FuncInfoId}{'Class'})
	{
		$ClassFunc{$Version}{$FuncDescr{$Version}{$FuncInfoId}{'Class'}}{$FuncInfoId} = 1;
	}
	$FuncDescr{$Version}{$FuncInfoId}{'Link'} = getFuncLink($FuncInfoId);
	if($FuncDescr{$Version}{$FuncInfoId}{'Link'} eq "Static")
	{#STATIC METHODS
		$FuncDescr{$Version}{$FuncInfoId}{'Static'} = "Yes";
	}
	else
	{
		$FuncDescr{$Version}{$FuncInfoId}{'Static'} = "No";
	}
	if($FuncDescr{$Version}{$FuncInfoId}{'MnglName'})
	{
		if($FuncDescr{$Version}{$FuncInfoId}{'MnglName'} =~ /\A_ZTV/)
		{
			$FuncDescr{$Version}{$FuncInfoId}{'Return'} = "";
		}
	}
	if($FuncDescr{$Version}{$FuncInfoId}{'ShortName'})
	{
		if($FuncDescr{$Version}{$FuncInfoId}{'ShortName'} =~ /\A_Z/)
		{
			$FuncDescr{$Version}{$FuncInfoId}{'ShortName'} = "";
		}
	}
}

sub isExteriorTypeType($)
{
	my $TypeType = $_[0];
	return (($TypeType eq "TemplateTypeParm") or ($TypeType eq "TypeName") or ($TypeType eq "TypeofType") or ($TypeType eq "TemplateTemplateParm") or ($TypeType eq "FunctionType") or ($TypeType eq "LangType") or ($TypeType eq "BoundTemplateTemplateParm"));
}

sub getTypeDescr($)
{
	my $TypeInfoId = $_[0];
	my $TypeId = getTypeId($TypeInfoId);
	my $HeaderName;
	my $HeaderLine;
	my $Spec;
	my $TypeType;
	my $NameSpaceId;
	my $TypeTypeByTypeId = getTypeTypeByTypeId($TypeId);
	if(isExteriorTypeType($TypeTypeByTypeId))
	{
		return;
	}
	if($TypeTypeByTypeId eq "Unknown")
	{
		$WARNINGS .= "WARNING:UNKNOWN TYPETYPE\n".$LibInfo{$Version}{$TypeId}{'info_type'}."\n";
		return;
	}
	$TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Access'} = getTypeAccess($TypeId);
	($TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Header'}, $TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Line'}) = getTypeHeader($TypeInfoId);
	if(($TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Header'} eq "<built-in>") or ($TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Header'} eq "<internal>"))
	{
		$TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Built-In'} = 1;
        $TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Header'} = "";
	}
	$TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Name'} = getTypeNameByInfo($TypeInfoId);
    $Dictionary_TypeName{$TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Name'}} = 1;
	if(isAnon($TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Name'}))
	{
		($HeaderName, $HeaderLine) = getLocation($TypeInfoId);
		$TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Name'} = "anon-";
		$TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Name'} .= $HeaderName."-".$HeaderLine;
	}
	$TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'ShortName'} = getTypeShortName($TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Name'});
	$TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Size'} = getSize($TypeId)/8;
	$TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Type'} = getTypeType($TypeInfoId, $TypeId);
    if(($TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Type'} eq "Struct") or ($TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Type'} eq "Class"))
    {
        getBaseClasses_Access($TypeInfoId, $TypeId);
    }
	if($TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Type'} eq "Typedef")
	{
		($TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'BaseType'}{'Tid'}, $TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'BaseType'}{'TDid'}, $Spec) = getBaseType($TypeInfoId, $TypeId);
	}
	if($TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Type'} ne "Intrinsic")
	{
		if(defined $HeaderDestination{$Version}{$TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Header'}})
		{
			$TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Library'} = $TargetLibraryName;
		}
	}
	$NameSpaceId = getNameSpaceId($TypeInfoId);
	if($NameSpaceId ne $TypeId)
	{
		$TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'NameSpace'} = getNameSpace($TypeInfoId);
	}
	if($TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'NameSpace'} and isNotAnon($TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Name'}))
	{
		$TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Name'} = $TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'NameSpace'}."::".$TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Name'};
	}
	if($TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Name'} =~ m/\Astd::/)
	{
		$TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Library'} = "libstdcxx";
	}
    $TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Name'} = correctName($TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Name'});
	getTypeMemb($TypeInfoId, $TypeId);
    $TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'Tid'} = $TypeId;
    $TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'TDid'} = $TypeInfoId;
}

sub getBaseClasses_Access($$)
{
    my $TypeInfoId = $_[0];
    my $TypeId = $_[1];
    my $Info = $LibInfo{$Version}{$TypeId}{'info'};
    if($Info =~ /binf[ ]*:[ ]*@([0-9]+) /)
    {
        $Info = $LibInfo{$Version}{$1}{'info'};
        while($Info =~ /accs[ ]*:[ ]*([a-z]+) /)
        {
            last if($Info !~ s/accs[ ]*:[ ]*([a-z]+) //o);
            my $Access = $1;
            last if($Info !~ s/binf[ ]*:[ ]*@([0-9]+) //o);
            my $BInfoId = $1;
            my $ClassId = getBinfClassId($BInfoId);
            if($Access eq "pub")
            {
                $TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'BaseClass'}{$ClassId} = "public";
            }
            elsif($Access eq "prot")
            {
                $TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'BaseClass'}{$ClassId} = "protected";
            }
            elsif($Access eq "priv")
            {
                $TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'BaseClass'}{$ClassId} = "private";
            }
            else
            {
                $TypeDescr{$Version}{$TypeInfoId}{$TypeId}{'BaseClass'}{$ClassId} = "private";
            }
        }
    }
}

sub getBinfClassId($)
{
    my $Info = $LibInfo{$Version}{$_[0]}{'info'};
    $Info =~ /type[ ]*:[ ]*@([0-9]+) /;
    return $1;
}

my %Mangled_Symbol_1=(
"double"=>"d",
"float"=>"f",
"int"=>"i",
"long"=>"l",
"short"=>"s",
"*"=>"P",
"&"=>"R",
"void"=>"v",
"const"=>"K"
);

my %Mangled_Symbol_2=(
"long int"=>"l",
"short int"=>"s",
"unsigned int"=>"j",
"long long"=>"x",
"unsigned long"=>"m",
"unsigned short"=>"t",
"double long"=>"e"
);

my %Mangled_Symbol_3=(
"unsigned short int"=>"t",
"long long int"=>"x",
"unsigned long int"=>"m"
);

sub cpp_mangle($)
{
    my $FuncInfoId = $_[0];
    my $MangledName = "_Z";
    $MangledName .= length($FuncDescr{$Version}{$FuncInfoId}{'ShortName'}).$FuncDescr{$Version}{$FuncInfoId}{'ShortName'};
    
    foreach my $ParamPos (sort {int($a) <=> int($b)} keys(%{$FuncDescr{$Version}{$FuncInfoId}{'Param'}}))
    {#Check Parameters
        my $ParamType_Id = $FuncDescr{$Version}{$FuncInfoId}{'Param'}{$ParamPos}{'type'};
        my $ParamType_DId = getTypeDeclId($ParamType_Id);
        my %ParamType = get_Type($ParamType_DId, $ParamType_Id, $Version);
        $MangledName .= type_mangle($ParamType{'Name'});
    }
    return $MangledName;
}

sub type_mangle($)
{
    my $Param_TypeName = $_[0];
    my $IsConst = $Param_TypeName =~ m/[ ]*K[ ]*/;
    my $P_num = 0;
    while($Param_TypeName =~ m/[ ]*P[ ]*/g){$P_num += 1;}
    my $IsRef = $Param_TypeName =~ m/[ ]*R[ ]*/;
    $Param_TypeName =~ s/[ ]*K[ ]*//g;
    $Param_TypeName =~ s/[ ]*R[ ]*//g;
    $Param_TypeName =~ s/[ ]*P[ ]*//g;
    $Param_TypeName = join(" ", sort {length($b) <=> length($a)} split(" ", $Param_TypeName));
    foreach my $Seq (keys(%Mangled_Symbol_3))
    {
        my $Symbol = $Mangled_Symbol_3{$Seq};
        $Param_TypeName =~ s/([ ]*)($Seq)([ ]*)/$1$Symbol$3/g;
    }
    foreach my $Seq (keys(%Mangled_Symbol_2))
    {
        my $Symbol = $Mangled_Symbol_2{$Seq};
        $Param_TypeName =~ s/([ ]*)($Seq)([ ]*)/$1$Symbol$3/g;
    }
    foreach my $Seq (keys(%Mangled_Symbol_1))
    {
        my $Symbol = $Mangled_Symbol_1{$Seq};
        $Seq =~ s*([^\w])*\\$1*g;
        $Param_TypeName =~ s/([ ]*)($Seq)([ ]*)/$1$Symbol$3/g;
    }
    my @Tokens = split(" ", $Param_TypeName);
    $Param_TypeName = "";
    foreach my $Token (@Tokens)
    {
        if(length($Token)>1)
        {
            $Param_TypeName .= " ".length($Token).$Token." ";
        }
        else
        {
            $Param_TypeName .= " ".$Token." ";
        }
    }
    if($IsConst)
    {
        $Param_TypeName = " K ".$Param_TypeName;
    }
    if($P_num>0)
    {
        foreach (1 .. $P_num)
        {
            $Param_TypeName = " P ".$Param_TypeName;
        }
    }
    if($IsRef)
    {
        $Param_TypeName = " R ".$Param_TypeName;
    }
    
    
    $Param_TypeName =~ s/ //g;
    return $Param_TypeName;
}

sub get_PureSignature($)
{#TODO: detect 'const' property
    my $FuncInfoId = $_[0];
    my $PureSignature = $FuncDescr{$Version}{$FuncInfoId}{'ShortName'};
    my $ClassType_Id = $FuncDescr{$Version}{$FuncInfoId}{'Class'};
    my $ClassType_DId = getTypeDeclId($ClassType_Id);
    my %ClassType = get_Type($ClassType_DId, $ClassType_Id, $Version);
    if($ClassType{'Name'})
    {
        $PureSignature = $ClassType{'Name'}."::".$PureSignature;
    }
    my @ParamTypes = ();
    foreach my $ParamPos (sort {int($a) <=> int($b)} keys(%{$FuncDescr{$Version}{$FuncInfoId}{'Param'}}))
    {#Check Parameters
        my $ParamType_Id = $FuncDescr{$Version}{$FuncInfoId}{'Param'}{$ParamPos}{'type'};
        my $ParamType_DId = getTypeDeclId($ParamType_Id);
        my %ParamType = get_Type($ParamType_DId, $ParamType_Id, $Version);
        @ParamTypes = (@ParamTypes, $ParamType{'Name'});
    }
    return $PureSignature."(".join(", ", @ParamTypes).")";
}

sub getFuncDescr($)
{
	my $FuncInfoId = $_[0];
    ($FuncDescr{$Version}{$FuncInfoId}{'Header'}, $FuncDescr{$Version}{$FuncInfoId}{'Line'}) = getFuncHeader($FuncInfoId);
	my $FuncKind = getFuncKind($FuncInfoId);
	if($FuncKind eq "PseudoTemplate")
    {
        delete $FuncDescr{$Version}{$FuncInfoId};
        return;
    }
    ($FuncDescr{$Version}{$FuncInfoId}{'ShortName'}, $FuncDescr{$Version}{$FuncInfoId}{'OperatorSymbol'}) = getFuncShortName(getFuncOrig($FuncInfoId));
    if($FuncDescr{$Version}{$FuncInfoId}{'ShortName'} =~ /\._/)
    {
        delete $FuncDescr{$Version}{$FuncInfoId};
        return;
    }
    getFuncParams($FuncInfoId);
    $FuncDescr{$Version}{$FuncInfoId}{'MnglName'} = getFuncMnglName($FuncInfoId);
    if(not $FuncDescr{$Version}{$FuncInfoId}{'MnglName'})
    {
        my $Library_Name = $LibInt_Short{$Version}{$FuncDescr{$Version}{$FuncInfoId}{'ShortName'}};
        if($Library_Name and $Lib_Language{$Version}{$Library_Name} eq "C++")
        {#this section only for c++ functions without class that have not been mangled in the tree
            my $PureSignature = get_PureSignature($FuncInfoId);
            $FuncDescr{$Version}{$FuncInfoId}{'MnglName'} = $mangled_name{$PureSignature};
            #TODO: Mangler of names (Alternative)
        }
        if(not $FuncDescr{$Version}{$FuncInfoId}{'MnglName'})
        {
            $FuncDescr{$Version}{$FuncInfoId}{'MnglName'} = $FuncDescr{$Version}{$FuncInfoId}{'ShortName'};
            $FuncDescr{$Version}{$FuncInfoId}{'Name'} = $FuncDescr{$Version}{$FuncInfoId}{'ShortName'};
        }
    }
    if(defined $LibInt{$Version}{$FuncDescr{$Version}{$FuncInfoId}{'MnglName'}})
    {
        $FuncDescr{$Version}{$FuncInfoId}{'SrcBin'} = "Both";
        $FuncDescr{$Version}{$FuncInfoId}{'Library'} = $TargetLibraryName;
    }
    else
    {#SrcOnly
        delete $FuncDescr{$Version}{$FuncInfoId};
        return;
    }
	$FuncDescr{$Version}{$FuncInfoId}{'Kind'} = $FuncKind;
	$FuncDescr{$Version}{$FuncInfoId}{'Return'} = getFuncReturn($FuncInfoId);
	if(($FuncKind eq "Constructor") or ($FuncKind eq "Destructor"))
	{
		$FuncDescr{$Version}{$FuncInfoId}{'Return'} = 0;
	}
	$FuncDescr{$Version}{$FuncInfoId}{'Type'} = getFuncType($FuncInfoId);
	$FuncDescr{$Version}{$FuncInfoId}{'Class'} = getFuncClass($FuncInfoId);
	if(($FuncDescr{$Version}{$FuncInfoId}{'Header'} eq "<built-in>") or ($FuncDescr{$Version}{$FuncInfoId}{'Header'} eq "<internal>"))
	{
		$FuncDescr{$Version}{$FuncInfoId}{'Built-In'} = 1;
        $FuncDescr{$Version}{$FuncInfoId}{'SrcBin'} = "BinOnly";
        $FuncDescr{$Version}{$FuncInfoId}{'Header'} = "";
	}
	$FuncDescr{$Version}{$FuncInfoId}{'Access'} = getFuncAccess($FuncInfoId);
	if($FuncDescr{$Version}{$FuncInfoId}{'Class'})
	{
		$ClassFunc{$Version}{$FuncDescr{$Version}{$FuncInfoId}{'Class'}}{$FuncInfoId} = 1;
	}
	$FuncDescr{$Version}{$FuncInfoId}{'Spec'} = getFuncSpec($FuncInfoId);
	$FuncDescr{$Version}{$FuncInfoId}{'Link'} = getFuncLink($FuncInfoId);
	if($FuncDescr{$Version}{$FuncInfoId}{'Spec'} eq "Virtual")
	{#VIRTUAL METHODS
		$FuncDescr{$Version}{$FuncInfoId}{'Virtual'} = "Yes";
	}
	elsif($FuncDescr{$Version}{$FuncInfoId}{'Spec'})
	{
		$FuncDescr{$Version}{$FuncInfoId}{'Virtual'} = "No";
	}
	if($FuncDescr{$Version}{$FuncInfoId}{'Spec'} eq "PureVirtual")
	{#VIRTUAL METHODS
		$FuncDescr{$Version}{$FuncInfoId}{'PureVirtual'} = "Yes";
	}
	elsif($FuncDescr{$Version}{$FuncInfoId}{'Spec'})
	{
		$FuncDescr{$Version}{$FuncInfoId}{'PureVirtual'} = "No";
	}
    if($FuncDescr{$Version}{$FuncInfoId}{'MnglName'} =~ /\A_Z/)
    {
	    if($FuncDescr{$Version}{$FuncInfoId}{'Type'} eq "Function")
	    {#STATIC METHODS
		    $FuncDescr{$Version}{$FuncInfoId}{'Static'} = "Yes";
	    }
	    elsif($FuncDescr{$Version}{$FuncInfoId}{'Type'} eq "Method")
	    {
		    $FuncDescr{$Version}{$FuncInfoId}{'Static'} = "No";
	    }
    }
	if($FuncDescr{$Version}{$FuncInfoId}{'Link'} eq "Static")
    {
        $FuncDescr{$Version}{$FuncInfoId}{'Static'} = "Yes";
    }
}

sub getTypeShortName($)
{
	my $TypeName = $_[0];
	$TypeName =~ s/\<.*\>//g;
	$TypeName =~ s/.*\:\://g;
	return $TypeName;
}

sub getBackRef($)
{
	my $TypeInfo = $LibInfo{$Version}{$_[0]}{'info'};
	if($TypeInfo =~ /name[ ]*:[ ]*@([0-9]+) /)
    {
	    return $1;
    }
    else
    {
        return "";
    }
}

sub getTypeId($)
{
	my $TypeInfo = $LibInfo{$Version}{$_[0]}{'info'};
	if($TypeInfo =~ /type[ ]*:[ ]*@([0-9]+) /)
    {
	    return $1;
    }
    else
    {
        return "";
    }
}

sub getFuncId($)
{
	my $FuncInfo = $LibInfo{$Version}{$_[0]}{'info'};
	if($FuncInfo =~ /type[ ]*:[ ]*@([0-9]+) /)
    {
	    return $1;
    }
    else
    {
        return "";
    }
}

sub getTypeMemb($$)
{
    my $TypeDeclId = $_[0];
	my $TypeId = $_[1];
	my $TypeInfo = $LibInfo{$Version}{$TypeId}{'info'};
	my $TypeMembInfoId;
	my $TypeType = $TypeDescr{$Version}{$TypeDeclId}{$TypeId}{'Type'};
	my $Position = 0;
    my $BasePosition = 0;
	my $TypeTypeInfoId;
	my $StructMembName;
	if($TypeType eq "Enum")
	{
		$TypeMembInfoId = getEnumMembInfoId($TypeId);
		while($TypeMembInfoId)
		{
			$TypeDescr{$Version}{$TypeDeclId}{$TypeId}{'Memb'}{$Position}{'value'} = getEnumMembVal($TypeMembInfoId);
			$TypeDescr{$Version}{$TypeDeclId}{$TypeId}{'Memb'}{$Position}{'name'} = getEnumMembName($TypeMembInfoId);
			$TypeMembInfoId = getNextMembInfoId($TypeMembInfoId);
			$Position += 1;
		}
	}
	elsif(($TypeType eq "Struct") or ($TypeType eq "Class") or ($TypeType eq "Union"))
	{
		$TypeMembInfoId = getStructMembInfoId($TypeId);
		while($TypeMembInfoId)
		{
            if($LibInfo{$Version}{$TypeMembInfoId}{'info_type'} ne "field_decl")
            {
                $TypeMembInfoId = getNextStructMembInfoId($TypeMembInfoId);
                next;
            }
            $StructMembName = getStructMembName($TypeMembInfoId);
            if($StructMembName =~ /_vptr\./)
            {#TODO: MERGE VIRTUAL TABLES
                $TypeMembInfoId = getNextStructMembInfoId($TypeMembInfoId);
                next;
            }
            if(not $StructMembName)
            {#TODO: MERGE BASE CLASSES DEFINITIONS
                $TypeDescr{$Version}{$TypeDeclId}{$TypeId}{'Base'}{$BasePosition}{'type'} = getStructMembType($TypeMembInfoId);
                $TypeDescr{$Version}{$TypeDeclId}{$TypeId}{'Base'}{$BasePosition}{'access'} = getStructMembAccess($TypeMembInfoId);
                $BasePosition += 1;
                $TypeMembInfoId = getNextStructMembInfoId($TypeMembInfoId);
                next;
            }
            $TypeDescr{$Version}{$TypeDeclId}{$TypeId}{'Memb'}{$Position}{'type'} = getStructMembType($TypeMembInfoId);
            $TypeDescr{$Version}{$TypeDeclId}{$TypeId}{'Memb'}{$Position}{'name'} = $StructMembName;
            $TypeDescr{$Version}{$TypeDeclId}{$TypeId}{'Memb'}{$Position}{'access'} = getStructMembAccess($TypeMembInfoId);
            $TypeDescr{$Version}{$TypeDeclId}{$TypeId}{'Memb'}{$Position}{'bitfield'} = getStructMembBitFieldSize($TypeMembInfoId);
            
			$TypeMembInfoId = getNextStructMembInfoId($TypeMembInfoId);
			$Position += 1;
		}
	}
}

sub isAnonTypedef($)
{
    my $TypeId = $_[0];
	if(isAnon(getTypeName($TypeId)))
	{
		return 0;
	}
	else
	{
		return isAnon(getTypeNameByInfo(anonTypedef($TypeId)));
	}
}

sub anonTypedef($)
{
	my $TypeId = $_[0];
	my $TypeMembInfoId;
	$TypeMembInfoId = getStructMembInfoId($TypeId);
	while($TypeMembInfoId)
	{
		my $NextTypeMembInfoId = getNextStructMembInfoId($TypeMembInfoId);
		if(not $NextTypeMembInfoId)
		{
			last;
		}
		$TypeMembInfoId = $NextTypeMembInfoId;
        if($LibInfo{$Version}{$TypeMembInfoId}{'info_type'} eq "type_decl" and getTypeNameByInfo($TypeMembInfoId) eq getTypeName($TypeId))
        {
            return 0;
        }
        
	}
	return $TypeMembInfoId;
}

sub getFuncParams($)
{
	my $FuncInfoId = $_[0];
	my $FuncInfo = $LibInfo{$Version}{$FuncInfoId}{'info'};
	my $FuncParamInfoId;
	my $Position = 0;
	my $FunctionType;
	my $FuncParamTypeId;
	$FuncParamInfoId = getFuncParamInfoId($FuncInfoId);
	$FunctionType = getFuncType($FuncInfoId);
	if($FunctionType eq "Method")
	{
		$FuncParamInfoId = getNextFuncParamInfoId($FuncParamInfoId);
	}
	while($FuncParamInfoId)
	{
		$FuncParamTypeId = getFuncParamType($FuncParamInfoId);
		last if($TypeDescr{$Version}{getTypeDeclId($FuncParamTypeId)}{$FuncParamTypeId}{'Name'} eq "void");
		
		if($TypeDescr{$Version}{getTypeDeclId($FuncParamTypeId)}{$FuncParamTypeId}{'Type'} eq "Restrict")
		{#DELETE RESTRICT SPEC
			$FuncParamTypeId = getRestrictBase($FuncParamTypeId);
		}
		$FuncDescr{$Version}{$FuncInfoId}{'Param'}{$Position}{'type'} = $FuncParamTypeId;
		$FuncDescr{$Version}{$FuncInfoId}{'Param'}{$Position}{'name'} = getFuncParamName($FuncParamInfoId);
        if(not $FuncDescr{$Version}{$FuncInfoId}{'Param'}{$Position}{'name'})
        {
            $FuncDescr{$Version}{$FuncInfoId}{'Param'}{$Position}{'name'} = "p".($Position+1);
        }
		$FuncParamInfoId = getNextFuncParamInfoId($FuncParamInfoId);
		$Position += 1;
	}
}

sub getRestrictBase($)
{
	my $TypeId = $_[0];
	my $TypeDeclId = getTypeDeclId($TypeId);
	my $BaseTypeId = $TypeDescr{$Version}{$TypeDeclId}{$TypeId}{'BaseType'}{'Tid'};
	my $BaseTypeDeclId = $TypeDescr{$Version}{$TypeDeclId}{$TypeId}{'BaseType'}{'TDid'};
	return $BaseTypeId;
}

sub getFuncAccess($)
{
	my $FuncInfo = $LibInfo{$Version}{$_[0]}{'info'};
	return "public" if($FuncInfo !~ /accs[ ]*:[ ]*([a-zA-Z]+) /);
	my $Access = $1;
	if($Access eq "pub")
	{
		return "public";
	}
	elsif($Access eq "prot")
	{
		return "protected";
	}
	elsif($Access eq "priv")
	{
		return "private";
	}
	else
	{
		return "public";
	}
}

sub getTypeAccess($)
{
	my $TypeInfo = $LibInfo{$Version}{$_[0]}{'info'};
	return "public" if($TypeInfo !~ /accs[ ]*:[ ]*([a-zA-Z]+) /);
	my $Access = $1;
	if($Access eq "prot")
	{
		return "protected";
	}
	elsif($Access eq "priv")
	{
		return "private";
	}
	elsif($Access eq "pub")
	{
		return "public";
	}
	else
	{
		return "public";
	}
}

sub getFuncKind($)
{
	my $FuncInfoId = $_[0];
	my $FuncInfo = $LibInfo{$Version}{$FuncInfoId}{'info'};
	if(($FuncInfo =~ m/note[ ]*:[ ]*pseudo tmpl /) or ($FuncInfo =~ m/ pseudo tmpl /))
	{
		return "PseudoTemplate";
	}
	elsif($FuncInfo =~ m/note[ ]*:[ ]*constructor /)
	{
		return "Constructor";
	}
	elsif($FuncInfo =~ m/note[ ]*:[ ]*destructor /)
	{
		return "Destructor";
	}
	elsif($FuncInfo =~ m/note[ ]*:[ ]*member /)
	{
		return "Normal";
	}
	elsif($FuncInfo =~ m/note[ ]*:[ ]*artificial /)
	{
		return "Normal";
	}
	elsif($FuncInfo =~ m/note[ ]*:[ ]*operator /)
	{
		return "Normal";
	}
	elsif($FuncInfo =~ m/ operator /)
	{
		return "Normal";
	}
	else
	{
		return "Normal";
	}
}

sub getFuncSpec($)
{
	my $FuncInfoId = $_[0];
	my $FuncInfo = $LibInfo{$Version}{$FuncInfoId}{'info'};
	if($FuncInfo =~ m/spec[ ]*:[ ]*pure /)
	{
		return "PureVirtual";
	}
	elsif($FuncInfo =~ m/spec[ ]*:[ ]*virt /)
	{
		return "Virtual";
	}
	else
	{
		if($FuncInfo =~ /spec[ ]*:[ ]*([a-zA-Z]+) /)
        {
		    return $1;
        }
        else
        {
            return "";
        }
	}
}

sub getFuncClass($)
{
	my $FuncInfoId = $_[0];
	my $FuncInfo = $LibInfo{$Version}{$FuncInfoId}{'info'};
	if($FuncInfo =~ /scpe[ ]*:[ ]*@([0-9]+) /)
    {
        return $1;
    }
    else
    {
        return "";
    }
}

sub getFuncLink($)
{
	my $FuncInfoId = $_[0];
	my $FuncInfo = $LibInfo{$Version}{$FuncInfoId}{'info'};
	if($FuncInfo =~ /link[ ]*:[ ]*static /)
	{
		return "Static";
	}
	else
	{
		if($FuncInfo =~ /link[ ]*:[ ]*([a-zA-Z]+) /)
        {
            return $1;
        }
        else
        {
            return "";
        }
	}
}

sub getNextFuncParamInfoId($)
{
	my $FuncInfoId = $_[0];
	my $FuncInfo = $LibInfo{$Version}{$FuncInfoId}{'info'};
	if($FuncInfo =~ /chan[ ]*:[ ]*@([0-9]+) /)
    {
        return $1;
    }
    else
    {
        return "";
    }
}

sub getFuncParamInfoId($)
{
	my $FuncInfoId = $_[0];
	my $FuncInfo = $LibInfo{$Version}{$FuncInfoId}{'info'};
	if($FuncInfo =~ /args[ ]*:[ ]*@([0-9]+) /)
    {
        return $1;
    }
    else
    {
        return "";
    }
}

sub getFuncParamType($)
{
	my $ParamInfoId = $_[0];
	my $ParamInfo = $LibInfo{$Version}{$ParamInfoId}{'info'};
	if($ParamInfo =~ /type[ ]*:[ ]*@([0-9]+) /)
    {
        return $1;
    }
    else
    {
        return "";
    }
}

sub getFuncParamName($)
{
	my $ParamInfoId = $_[0];
	my $NameInfoId;
	my $FuncParamName;
	my $ParamInfo = $LibInfo{$Version}{$ParamInfoId}{'info'};
	return "" if($ParamInfo !~ /name[ ]*:[ ]*@([0-9]+) /);
	$NameInfoId = $1;
	return "" if($LibInfo{$Version}{$NameInfoId}{'info'} !~ /strg[ ]*:[ ]*(.*)[ ]+lngt/);
	$FuncParamName = $1;
	$FuncParamName =~ s/[ ]+\Z//g;
	return $FuncParamName;
}

sub getEnumMembInfoId($)
{
	my $TypeInfoId = $_[0];
	my $TypeInfo = $LibInfo{$Version}{$TypeInfoId}{'info'};
	if($TypeInfo =~ /csts[ ]*:[ ]*@([0-9]+) /)
    {
        return $1;
    }
    else
    {
        return "";
    }
}

sub getStructMembInfoId($)
{
	my $TypeInfoId = $_[0];
	my $TypeInfo = $LibInfo{$Version}{$TypeInfoId}{'info'};
	if($TypeInfo =~ /flds[ ]*:[ ]*@([0-9]+) /)
    {
        return $1;
    }
    else
    {
        return "";
    }
}

sub getNameSpace($)
{
	my $TypeInfoId = $_[0];
	my $TypeInfo = $LibInfo{$Version}{$TypeInfoId}{'info'};
	my $NameSpaceInfoId;
	my $NameSpaceId;
	my $NameSpaceIdentifier;
	my $NameSpace;
    my $NameSpaceInfo;
	return "" if($TypeInfo !~ /scpe[ ]*:[ ]*@([0-9]+) /);
	$NameSpaceInfoId = $1;
	if($LibInfo{$Version}{$NameSpaceInfoId}{'info_type'} eq "namespace_decl")
	{
		$NameSpaceInfo = $LibInfo{$Version}{$NameSpaceInfoId}{'info'};
		return "" if($NameSpaceInfo !~ /name[ ]*:[ ]*@([0-9]+) /);
		$NameSpaceId = $1;
		$NameSpaceIdentifier = $LibInfo{$Version}{$NameSpaceId}{'info'};
		return "" if($NameSpaceIdentifier !~ /strg[ ]*:[ ]*(.*)[ ]+lngt/);
		$NameSpace = $1;
		$NameSpace =~ s/[ ]+\Z//g;
		return $NameSpace;
	}
	elsif($LibInfo{$Version}{$NameSpaceInfoId}{'info_type'} eq "record_type")
	{
		return getTypeName($NameSpaceInfoId);
	}
	else
	{
		return "";
	}
}

sub getNameSpaceId($)
{
	my $TypeInfoId = $_[0];
	my $TypeInfo = $LibInfo{$Version}{$TypeInfoId}{'info'};
	if($TypeInfo =~ /scpe[ ]*:[ ]*@([0-9]+) /)
    {
	    return $1;
    }
    else
    {
        return "";
    }
}

sub getEnumMembName($)
{
	my $TypeMembInfoId = $_[0];
	return "" if($LibInfo{$Version}{$TypeMembInfoId}{'info'} !~ /purp[ ]*:[ ]*@([0-9]+)/);
	my $Purp = $1;
	return "" if($LibInfo{$Version}{$Purp}{'info'} !~ /strg[ ]*:[ ]*(.*)[ ]+lngt/);
	my $EnumMembName = $1;
	$EnumMembName =~ s/[ ]+\Z//g;
	return $EnumMembName;
}

sub getStructMembName($)
{
	my $TypeMembInfoId = $_[0];
	return "" if($LibInfo{$Version}{$TypeMembInfoId}{'info'} !~ /name[ ]*:[ ]*@([0-9]+) /);
	my $NameInfoId = $1;
	return "" if($LibInfo{$Version}{$NameInfoId}{'info'} !~ /strg[ ]*:[ ]*(.*)[ ]+lngt/);
	my $StructMembName = $1;
	$StructMembName =~ s/[ ]+\Z//g;
	return $StructMembName;
}

sub getEnumMembVal($)
{
	my $TypeMembInfoId = $_[0];
	return "" if($LibInfo{$Version}{$TypeMembInfoId}{'info'} !~ /valu[ ]*:[ ]*@([0-9]+) /);
	my $Valu = $1;
	if($LibInfo{$Version}{$Valu}{'info'} =~ /low[ ]*:[ ]*(-?[0-9]+) /)
    {
        return $1;
    }
    else
    {
        return "";
    }
}

sub getSize($)
{
	my $Info = $LibInfo{$Version}{$_[0]}{'info'};
	if($Info =~ /size[ ]*:[ ]*@([0-9]+) /)
	{
        my $SizeInfoId = $1;
		if($LibInfo{$Version}{$SizeInfoId}{'info'} =~ /low[ ]*:[ ]*(-?[0-9]+) /)
        {
		    return $1;
        }
        else
        {
            return "";
        }
	}
	else
	{
		return 0;
	}
}

sub getStructMembType($)
{
	my $TypeMembInfoId = $_[0];
	if($LibInfo{$Version}{$TypeMembInfoId}{'info'} =~ /type[ ]*:[ ]*@([0-9]+) /)
    {
        return $1;
    }
    else
    {
        return "";
    }
}

sub getStructMembBitFieldSize($)
{
	my $TypeMembInfoId = $_[0];
	if($LibInfo{$Version}{$TypeMembInfoId}{'info'} =~ / bitfield /)
	{
		return getSize($TypeMembInfoId);
	}
	else
	{
		return 0;
	}
}

sub getStructMembAccess($)
{
	my $Access;
	my $MembInfo = $LibInfo{$Version}{$_[0]}{'info'};
	return "public" if($MembInfo !~ /accs[ ]*:[ ]*([a-zA-Z]+) /);
	$Access = $1;
	if($Access eq "pub")
	{
		return "public";
	}
	elsif($Access eq "prot")
	{
		return "protected";
	}
	elsif($Access eq "priv")
	{
		return "private";
	}
	else
	{
		return "public";
	}
}

sub getNextMembInfoId($)
{
	my $TypeMembInfoId = $_[0];
	if($LibInfo{$Version}{$TypeMembInfoId}{'info'} =~ /chan[ ]*:[ ]*@([0-9]+) /)
    {
        return $1;
    }
    else
    {
        return "";
    }
}

sub getNextStructMembInfoId($)
{
	my $TypeMembInfoId = $_[0];
	if($LibInfo{$Version}{$TypeMembInfoId}{'info'} =~ /chan[ ]*:[ ]*@([0-9]+) /)
    {
        return $1;
    }
    else
    {
        return "";
    }
}

sub fieldHasName($)
{
	my $TypeMembInfoId = $_[0];
	if($LibInfo{$Version}{$TypeMembInfoId}{'info_type'} eq "field_decl")
	{
		if($LibInfo{$Version}{$TypeMembInfoId}{'info'} =~ /name[ ]*:[ ]*@([0-9]+) /)
        {
            return $1;
        }
        else
        {
            return "";
        }
	}
	else
	{
		return 0;
	}
}

sub getTypeHeader($)
{
	my $TypeInfo = $LibInfo{$Version}{$_[0]}{'info'};
	if($TypeInfo =~ /srcp[ ]*:[ ]*([0-9a-zA-Z\_\-\<\>\.\+]+):([0-9]+) /)
    {
        return ($1, $2);
    }
    else
    {
        return ();
    }
}

sub getFuncHeader($)
{
	my $FuncInfo = $LibInfo{$Version}{$_[0]}{'info'};
	if($FuncInfo =~ /srcp[ ]*:[ ]*([0-9a-zA-Z\_\-\<\>\.\+]+):([0-9]+) /)
    {
	    return ($1, $2);
    }
    else
    {
        return ();
    }
}

sub headerSearch($)
{
    my $LibVersion = $_[0];
	foreach my $Dest (split("\n", $Descriptor{$LibVersion}{'Headers'}))
	{
        $Dest =~ s/\A[ ]*//g;
        $Dest =~ s/[ ]*\Z//g;
        next if(not $Dest);
        if($Descriptor{$LibVersion}{'Dir'})
        {
            $Dest = $Descriptor{$LibVersion}{'Dir'}."/".$Dest if($Dest !~ m{\A/});
        }
        $Dest = $ENV{'PWD'}."/".$Dest if($Dest !~ m{\A/});
		foreach my $Destination (split("\n", `find $Dest -type f`))
		{
			chomp($Destination);
			next if(not headerFilter($Destination));
            my $Header = get_FileName_ByPath($Destination);
			$DestinationHeader{$LibVersion}{$Destination} = $Header;
			$HeaderDestination{$LibVersion}{$Header} = $Destination;
			$HeaderDirs{$LibVersion}{get_Dir_ByPath($Destination)} = 1;
		}
        foreach my $Dir (split("\n", `find $Dest -type d`))
        {
            chomp($Dir);
            $HeaderDirs{$LibVersion}{$Dir} = 1;
        }
	}

    foreach my $Dest (split("\n", $Descriptor{$LibVersion}{'Include_Paths'}))
    {
        $Dest =~ s/\A[ ]*//g;
        $Dest =~ s/[ ]*\Z//g;
        next if(not $Dest);
        if($Descriptor{$LibVersion}{'Dir'})
        {
            $Dest = $Descriptor{$LibVersion}{'Dir'}."/".$Dest if($Dest !~ m{\A/});
        }
        $Dest = $ENV{'PWD'}."/".$Dest if($Dest !~ m{\A/});
        my @Dirs = split("\n", `find $Dest -type d`);
        foreach my $Dir (@Dirs)
        {
            $HeaderDirs{$LibVersion}{$Dir} = 1;
        }
    }
}

sub get_FileName_ByPath($)
{
    my $Destination = $_[0];
    if($Destination =~ /\A(.*\/)([^\/]*)\Z/)
    {
        return $2;
    }
    else
    {
        return $Destination;
    }
}

sub get_Dir_ByPath($)
{
    my $Destination = $_[0];
    return "" if($Destination =~ m*\A\./*);
    if($Destination =~ /\A(.*)\/([^\/]*)\Z/)
    {
        return $1;
    }
    else
    {
        return "";
    }
}

sub escapeSymb($)
{
	my $Str = $_[0];
	$Str =~ s/([^\w])/\\$1/g;
	return $Str;
}

sub getLocation($)
{
	my $TypeInfo = $LibInfo{$Version}{$_[0]}{'info'};
	if($TypeInfo =~ /srcp[ ]*:[ ]*([0-9a-zA-Z\_\-\<\>\.\+]+):([0-9]+) /)
    {
	    return ($1, $2);
    }
    else
    {
        return ();
    }
}

sub getTypeType($$)
{
	my $TypeId = $_[1];
	my $TypeDeclId = $_[0];
	my $TypeInfo;
	my $TypeTypeInfoId;
	my $TypeType;
	my $TypeTypeByHeader;
	my $BaseTypeDeclId;
	#CONST
	return "Const" if(($LibInfo{$Version}{$TypeId}{'info'} =~ m/qual[ ]*:[ ]*c /) and ($LibInfo{$Version}{$TypeId}{'info'} =~ m/unql[ ]*:[ ]*\@/));
	#TYPEDEFS
	return "Typedef" if(($LibInfo{$Version}{$TypeId}{'info'} =~ m/unql[ ]*:/) and not ($LibInfo{$Version}{$TypeId}{'info'} =~ m/qual[ ]*:/));
	#VOLATILES
	return "Volatile" if(($LibInfo{$Version}{$TypeId}{'info'} =~ m/qual[ ]*:[ ]*v /) and ($LibInfo{$Version}{$TypeId}{'info'} =~ m/unql[ ]*:[ ]*\@/));
	#RESTRICT
	return "Restrict" if(($LibInfo{$Version}{$TypeId}{'info'} =~ m/qual[ ]*:[ ]*r /) and ($LibInfo{$Version}{$TypeId}{'info'} =~ m/unql[ ]*:[ ]*\@/));
	if((not $LibInfo{$Version}{$TypeId}{'info'} =~ m/qual[ ]*:/) and (not $LibInfo{$Version}{$TypeId}{'info'} =~ m/unql[ ]*:[ ]*\@/))
	{#ANON TYPEDEF
		if(isAnonTypedef($TypeId))
		{
			$BaseTypeDeclId = anonTypedef($TypeId);
			if(($TypeDeclId ne $BaseTypeDeclId) or ($TypeId ne getTypeId($BaseTypeDeclId)))
			{
				return "Typedef";
			}
		}
	}
	#TYPE TYPE
	$TypeType = getTypeTypeByTypeId($TypeId);
	if($TypeType eq "Struct")
	{
		if($TypeDeclId)
		{
			if($LibInfo{$Version}{$TypeDeclId}{'info_type'} eq "template_decl")
			{#TEMPLATES
				return "Template";
			}
			elsif(getTypeNameByInfo($TypeDeclId) =~ m/<.*>[^:]*/)
			{#TEMPLATE INSTANCES
				return "TemplateInstance";
			}
			else
			{
				return "Struct";
			}
		}
		else
		{
			if(getTypeName($TypeId) =~ m/<.*>[^:]*/)
			{#TEMPLATE INSTANCES
				return "TemplateInstance";
			}
			else
			{
				return "Struct";
			}
		}
	}
	else
	{
		return $TypeType;
	}
	
}

sub getTypeTypeByTypeId($)
{
	my $TypeId = $_[0];
	my $TypeType = $LibInfo{$Version}{$TypeId}{'info_type'};
	if(($TypeType eq "integer_type") or ($TypeType eq "real_type") or ($TypeType eq "boolean_type") or ($TypeType eq "void_type"))
	{
		return "Intrinsic";
	}
	elsif(isFuncPtr($TypeId))
	{
		return "FuncPtr";
	}
	elsif($TypeType eq "pointer_type")
	{
		return "Pointer";
	}
	elsif($TypeType eq "reference_type")
	{
		return "Ref";
	}
	elsif($TypeType eq "union_type")
	{
		return "Union";
	}
	elsif($TypeType eq "enumeral_type")
	{
		return "Enum";
	}
	elsif($TypeType eq "record_type")
	{
		return "Struct";
	}
	elsif($TypeType eq "typename_type")
	{
		return "TypeName";
	}
	elsif($TypeType eq "template_type_parm")
	{
		return "TemplateTypeParm";
	}
	elsif($TypeType eq "template_template_parm")
	{
		return "TemplateTemplateParm";
	}
	elsif($TypeType eq "typeof_type")
	{
		return "TypeofType";
	}
	elsif($TypeType eq "array_type")
	{
		return "Array";
	}
	elsif($TypeType eq "lang_type")
	{
		return "LangType";
	}
	elsif($TypeType eq "complex_type")
	{
		return "Intrinsic";
	}
	elsif($TypeType eq "function_type")
	{
		return "FunctionType";
	}
	elsif($TypeType eq "bound_template_template_parm")
	{
		return "BoundTemplateTemplateParm";
	}
	else
	{
		return "Unknown";
	}
}

sub getTypeNameByInfo($)
{
	my $TypeInfo = $LibInfo{$Version}{$_[0]}{'info'};
	my $TypeNameInfoId;
	my $TypeName;
	return "" if($TypeInfo !~ /name[ ]*:[ ]*@([0-9]+) /);
	$TypeNameInfoId = $1;
	return "" if($LibInfo{$Version}{$TypeNameInfoId}{'info'} !~ /strg[ ]*:[ ]*(.*)[ ]+lngt/);
	$TypeName = $1;
	$TypeName =~ s/[ ]+\Z//g;
	return $TypeName;
}

sub getFuncShortName($)
{
	my $FuncInfo = $LibInfo{$Version}{$_[0]}{'info'};
	my $FuncName;
	my $FuncId;
	my $OperatorSymbol;
	return () if($FuncInfo !~ /name[ ]*:[ ]*@([0-9]+) /);
	my $FuncNameInfoId = $1;
	if($FuncInfo =~ m/ operator /)
	{
		if($FuncInfo =~ m/note[ ]*:[ ]*conversion /)
		{
			$OperatorSymbol = $TypeDescr{$Version}{getTypeDeclId($FuncDescr{$Version}{$_[0]}{'Return'})}{$FuncDescr{$Version}{$_[0]}{'Return'}}{'Name'};
			return ("operator $OperatorSymbol", $OperatorSymbol);
		}
		return () if($FuncInfo !~ / operator[ ]+([a-zA-Z]+) /);
		$OperatorSymbol = $Operator_Indication{$1};
		$FuncName = "operator$OperatorSymbol";
		return ($FuncName, $OperatorSymbol);
	}
	return () if($LibInfo{$Version}{$FuncNameInfoId}{'info'} !~ /strg[ ]*:[ ]*(.*)[ ]+lngt/);
	$FuncName = $1;
	$FuncName =~ s/[ ]+\Z//g;
	return ($FuncName, "");
}

sub getFuncMnglName($)
{
	my $FuncInfo = $LibInfo{$Version}{$_[0]}{'info'};
	my $FuncMnglNameInfoId;
	my $FuncMnglName;
	return "" if($FuncInfo !~ /mngl[ ]*:[ ]*@([0-9]+) /);
	$FuncMnglNameInfoId = $1;
	return "" if($LibInfo{$Version}{$FuncMnglNameInfoId}{'info'} !~ /strg[ ]*:[ ]*([^ ]*)[ ]+/);
	$FuncMnglName = $1;
	$FuncMnglName =~ s/[ ]+\Z//g;
	return $FuncMnglName;
}

sub getFuncReturn($)
{
	my $FuncInfo = $LibInfo{$Version}{$_[0]}{'info'};
	my $FuncTypeInfoId;
	my $FuncReturnTypeId;
	return "" if($FuncInfo !~ /type[ ]*:[ ]*@([0-9]+) /);
	$FuncTypeInfoId = $1;
	return "" if($LibInfo{$Version}{$FuncTypeInfoId}{'info'} !~ /retn[ ]*:[ ]*@([0-9]+) /);
	$FuncReturnTypeId = $1;
	if($TypeDescr{$Version}{getTypeDeclId($FuncReturnTypeId)}{$FuncReturnTypeId}{'Type'} eq "Restrict")
	{#DELETE RESTRICT SPEC
		$FuncReturnTypeId = getRestrictBase($FuncReturnTypeId);
	}
	return $FuncReturnTypeId;
}

sub getFuncOrig($)
{
	my $FuncInfo = $LibInfo{$Version}{$_[0]}{'info'};
	my $FuncOrigInfoId;
	return $_[0] if($FuncInfo !~ /orig[ ]*:[ ]*@([0-9]+) /);
	return $1;
}

sub getFuncName($)
{
	my $FuncInfoId = $_[0];
	return getFuncNameByUnmngl($FuncInfoId);
}

sub getVarName($)
{
	my $FuncInfoId = $_[0];
	return getFuncNameByUnmngl($FuncInfoId);
}

#MNGL NAMES
sub getFuncNameByUnmngl($)
{
	my $FuncInfoId = $_[0];
	return unmangle($FuncDescr{$Version}{$FuncInfoId}{'MnglName'});
}

my %UnmangledName;
sub unmangle($)
{
    my $Interface_Name = $_[0];
    return "" if(not $Interface_Name);
    if($UnmangledName{$Interface_Name})
    {
        return $UnmangledName{$Interface_Name};
    }
    if($Interface_Name !~ /\A_Z/)
    {
        return $Interface_Name;
    }
    my $Unmangled = `c++filt $Interface_Name`;
    chomp($Unmangled);
    $UnmangledName{$Interface_Name} = $Unmangled;
    return $Unmangled;
}

sub unmangleArray(@)
{
    my $UnmangleCommand = "c++filt ".join(" ", @_);
    return split("\n", `$UnmangleCommand`);
}

sub get_Signature($$)
{
	my $Func_Name = $_[0];
    my $LibVersion = $_[1];
    if(not defined $Functions{$LibVersion}{$Func_Name})
    {
        if($Func_Name =~ /\A_Z/)
        {
            return $tr_name{$Func_Name};
        }
        else
        {
            return $Func_Name;
        }
    }
    return $Cache{'get_Signature'}{$Func_Name}{$LibVersion} if($Cache{'get_Signature'}{$Func_Name}{$LibVersion});
	my $Func_Signature = "";
    my @Param_Types_FromUnmangledName = ();
    my $ShortName = $Functions{$LibVersion}{$Func_Name}{'ShortName'};
    if($Func_Name =~ /\A_Z/)
    {
        if($tr_name{$Func_Name} =~ /\A(.*[ :~]$ShortName[ ]*)\(.*\)[^()]*\Z/)
        {
            $Func_Signature = $1;
        }
        elsif($tr_name{$Func_Name} =~ /\A(.*[ :~]$ShortName[ ]*)\Z/)
        {#Variables
            $Func_Signature = $1;
        }
        else
        {
            $Func_Signature = $ShortName;
        }
        @Param_Types_FromUnmangledName = get_Signature_Parts($tr_name{$Func_Name});
    }
    else
    {
        $Func_Signature = $Func_Name;
    }
    if(not $Func_Signature)
    {
        if($Func_Name =~ /\A_Z/)
        {   
            return $tr_name{$Func_Name};
        }
        else
        {
            return $Func_Name;
        }
    }
    
	my @ParamArray;
	foreach my $Pos (sort {int($a) <=> int($b)} keys(%{$Functions{$LibVersion}{$Func_Name}{'Param'}}))
	{
        my $ParamTypeId = $Functions{$LibVersion}{$Func_Name}{'Param'}{$Pos}{'type'};
        my $ParamTypeName = $TypeDescr{$LibVersion}{getTypeDeclId_by_Ver($ParamTypeId, $LibVersion)}{$ParamTypeId}{'Name'};
        $ParamTypeName = $Param_Types_FromUnmangledName[$Pos] if(not $ParamTypeName);
        my $ParamName = $Functions{$LibVersion}{$Func_Name}{'Param'}{$Pos}{'name'};
        if($ParamName)
        {
		    push(@ParamArray, $ParamTypeName." ".$ParamName);
        }
        else
        {
            push(@ParamArray, $ParamTypeName);
        }
	}
    if($tr_name{$Func_Name} !~ /\A(.*[ :~]$ShortName[ ]*)\Z/)
    {
	    $Func_Signature .= " (".join(", ", @ParamArray).")";
    }
    $Cache{'get_Signature'}{$Func_Name}{$LibVersion} = $Func_Signature;
	return $Func_Signature;
}

sub getVarNameByAttr($)
{
	my $FuncInfoId = $_[0];
	my $VarName;
	return "" if(not $FuncDescr{$Version}{$FuncInfoId}{'ShortName'});
	if($FuncDescr{$Version}{$FuncInfoId}{'Class'})
	{
		$VarName .= $TypeDescr{$Version}{getTypeDeclId($FuncDescr{$Version}{$FuncInfoId}{'Class'})}{$FuncDescr{$Version}{$FuncInfoId}{'Class'}}{'Name'};
		$VarName .= "::";
	}
	$VarName .= $FuncDescr{$Version}{$FuncInfoId}{'ShortName'};
	return $VarName;
}

sub mangleFuncName($)
{
	my $FuncId = $_[0];
}

sub getFuncType($)
{
	my $FuncInfo = $LibInfo{$Version}{$_[0]}{'info'};
	my $FuncTypeInfoId;
	my $FunctionType;
	return "" if($FuncInfo !~ /type[ ]*:[ ]*@([0-9]+) /);
	$FuncTypeInfoId = $1;
	$FunctionType = $LibInfo{$Version}{$FuncTypeInfoId}{'info_type'};
	if($FunctionType eq "method_type")
	{
		return "Method";
	}
	elsif($FunctionType eq "function_type")
	{
		return "Function";
	}
	else
	{
		return $FunctionType;
	}
}

sub getFuncs_Class($)
{
	my $TypeId = $_[0];
	return keys(%{$ClassFunc{$Version}{$TypeId}});
}

sub isNotAnon($)
{
	return (not isAnon($_[0]));
}

sub isAnon($)
{
	return (($_[0] =~ m/\.\_[0-9]+/) or ($_[0] =~ m/anon-/));
}

sub unmangled_Compact($$)
#Throws all non-essential (for C++ language) whitespaces from a string.  If 
#the whitespace is essential it will be replaced with exactly one ' ' 
#character. Works correctly only for unmangled names.
#If level > 1 is supplied, can relax its intent to compact the string.
{
  my $result=$_[0];
  my $level = $_[1] || 1;
  my $o1 = ($level>1)?' ':'';
  #First, we reduce all spaces that we can
  my $coms='[-()<>:*&~!|+=%@~"?.,/[^'."']";
  my $coms_nobr='[-()<:*&~!|+=%@~"?.,'."']";
  my $clos='[),;:\]]';
  $result=~s/^\s+//gm;
  $result=~s/\s+$//gm;
  $result=~s/((?!\n)\s)+/ /g;
  $result=~s/([a-zA-Z0-9_]+)\s+($coms+)/$1$o1$2/gm;
  #$result=~s/([a-zA-Z0-9_])(\()/$1$o1$2/gm if $o1;
  $result=~s/($coms+)\s+([a-zA-Z0-9_]+)/$1$o1$2/gm;
  $result=~s/(\()\s+([a-zA-Z0-9_])/$1$2/gm if $o1;
  $result=~s/(\w)\s+($clos)/$1$2/gm;
  $result=~s/($coms+)\s+($coms+)/$1 $2/gm;
  $result=~s/($coms_nobr+)\s+($coms+)/$1$o1$2/gm;
  $result=~s/($coms+)\s+($coms_nobr+)/$1$o1$2/gm;
  #don't forget about >> and <:.  In unmangled names global-scope modifier 
  #is not used, so <: will always be a digraph and requires no special treatment.
  #We also try to remove other parts that are better to be removed here than in other places
  #double-cv
  $result=~s/\bconst\s+const\b/const/gm;
  $result=~s/\bvolatile\s+volatile\b/volatile/gm;
  $result=~s/\bconst\s+volatile\b\s+const\b/const volatile/gm;
  $result=~s/\bvolatile\s+const\b\s+volatile\b/const volatile/gm;
  #Place cv in proper order
  $result=~s/\bvolatile\s+const\b/const volatile/gm;
  return $result;
}

sub unmangled_PostProcess($)
{
  my $result = $_[0];
  #s/\bunsigned int\b/unsigned/g;
  $result =~ s/\bshort unsigned int\b/unsigned short/g;
  $result =~ s/\bshort int\b/short/g;
  $result =~ s/\blong long unsigned int\b/unsigned long long/g;
  $result =~ s/\blong unsigned int\b/unsigned long/g;
  $result =~ s/\blong long int\b/long long/g;
  $result =~ s/\blong int\b/long/g;
  $result =~ s/\)const\b/\) const/g;
  $result =~ s/\blong long unsigned\b/unsigned long long/g;
  $result =~ s/\blong unsigned\b/unsigned long/g;
  return $result;
}

# From libtodb2/libtodb.pm
# Trim string spaces.
sub trim($)
{
        my $string = shift;
        $string =~ s/^\s+//;
        $string =~ s/\s+$//;
        return $string;
}
# Different names corrections
sub correctName($)
{
    my $CorrectName = $_[0];
    $CorrectName = unmangled_Compact($CorrectName, 1);
    $CorrectName = unmangled_PostProcess($CorrectName);
	#my $CorrectName = correctName_Orig($_[0]);
	#$CorrectName =~ s/[ ]+\Z//g;
	return $CorrectName;
}
sub correctName_Orig($)
{
    my $s = $_[0];
    $s = trim($s);

    if( $s eq "unsigned" || $s eq "int unsigned" ) {
      return "unsigned int";
    }

    if( $s eq "long" || $s eq "int long" ) {
      return "long int";
    }

    if( $s eq "short" || $s eq "int short" ) {
      return "short int";
    }

    if($s eq "long long" || $s eq "long int long" || $s eq "int long long" ) {
      return "long long int";
    }

    if(   $s eq "unsigned long" || $s eq "unsigned int long" || $s eq "int unsigned long"
       || $s eq "long unsigned int" || $s eq "long int unsigned" ) {
      return "unsigned long int";
    }

    if(   $s eq "unsigned short" || $s eq "unsigned int short" || $s eq "int unsigned short"
        || $s eq "short unsigned int" || $s eq "short int unsigned" ) {
       return "unsigned short";
    }

    if(   $s eq "unsigned long long" || $s eq "long unsigned long" || $s eq "long long unsigned"
        || $s eq "unsigned long int long" || $s eq "unsigned int long long" || $s eq "int unsigned long long"
        || $s eq "long unsigned long int" || $s eq "long unsigned int long" || $s eq "long int unsigned long"
        || $s eq "int long unsigned long"
        || $s eq "long long unsigned int" || $s eq "long long int unsigned" || $s eq "long int long unsigned"
        || $s eq "int long long unsigned" ) {
       return "unsigned long long int";
    }

    $s =~ s/<nullbase-(\d|\w)+>/void/g;

    if( $s =~ /<ENUM-(.+)>/ ) {
	my $num = $1;
	$s =~ s/<ENUM-$num>/anon-enum-$num/g;
    }
    elsif( $s =~ /<UN-TYPE-(.+)>/ ) {
	my $num = $1;
	$s =~ s/<UN-TYPE-$num>/anon-union-$num/g;
    }
    elsif( $s =~ /<STR-TYPE-(.+)>/ ) {
	my $num = $1;
	$s =~ s/<STR-TYPE-$num>/anon-struct-$num/g;
    }
    
    $s =~ s/(\w)\*/$1 \*/g;
    $s =~ s/(\w)\&/$1 \&/g;
    $s =~ s/(.+)volatile ?((\&|\*)?$)/volatile $1$2/;
    $s =~ s/(.+)const ?((\&|\*)?$)/const $1$2/;

	while ($s =~ /\* \*/) {
    	$s =~ s/\* \*/\*\*/g;
    }

    $s =~ s/,/, /g;	
    $s =~ s/  / /g;	
    return $s;
}

#get Dump
sub getDump_AllInOne()
{
    `mkdir -p temp`;
    `rm -fr temp/*`;
	my $HeaderIncludes;
	my @AddOptArr = keys(%{$HeaderDirs{$Version}});
	my $AddOpt = join(" -I", @AddOptArr);
    $AddOpt ="-I".$AddOpt;
    $AddOpt =~ s/ /\ /g;
	foreach my $Destination (sort keys(%{$DestinationHeader{$Version}}))
	{
		$HeaderIncludes .= "#include<$Destination>\n";
	}
	return "" if(not $HeaderIncludes);
    my $Lib_VersionName = $TargetLibraryName."_v".$Version;
	open(LIB_HEADER, ">temp/$Lib_VersionName.h");
	print LIB_HEADER $HeaderIncludes;
	close(LIB_HEADER);
	system("g++ >header_compile_errors/$TargetLibraryName/$Descriptor{$Version}{'Version'} 2>&1 -fdump-translation-unit temp/$Lib_VersionName.h $CompilerOptions{$Version} $AddOpt");
    if($?)
    {
        print "WARNING: some errors have occured while headers compilation\nyou can see compilation errors in the file header_compile_errors/$TargetLibraryName/$Descriptor{$Version}{'Version'}\n";
    }
    `mv -f $Lib_VersionName.h*.tu temp/`;
	return (split("\n", `find temp -maxdepth 1 -name "$Lib_VersionName\.h*\.tu"`))[0];
}

sub getDump_Separately($)
{
    `mkdir -p temp`;
    `rm -fr temp/*`;
	my $Destination = $_[0];
	my @AddOptArr = keys(%{$HeaderDirs{$Version}});
	my $AddOpt = join(" -I", @AddOptArr);
    $AddOpt ="-I".$AddOpt;
    $AddOpt =~ s/ /\ /g;
    my $Lib_VersionName = $TargetLibraryName."_v".$Version;
	open(LIB_HEADER, ">temp/$Lib_VersionName.h");
	if($TargetLibraryName eq "freetype2" and not $Include_Preamble{'ft2build.h'})
    {
        print LIB_HEADER "#include<ft2build.h>\n";
    }
    elsif($TargetLibraryName eq "libxml2" and not $Include_Preamble{'tree.h'})
    {
        print LIB_HEADER "#include<tree.h>\n";
    }
    foreach my $Preamble_Header (keys(%Include_Preamble))
    {
        print LIB_HEADER "#include<$Preamble_Header>\n";
    }
	print LIB_HEADER "#include<$Destination>\n";
	close(LIB_HEADER);
	system("g++ >>header_compile_errors/$TargetLibraryName/$Descriptor{$Version}{'Version'} 2>&1 -fdump-translation-unit temp/$Lib_VersionName.h $CompilerOptions{$Version} $AddOpt");
    if($?)
    {
        $HeaderCompileError{getHeaderStandaloneName($Destination)} = 1;
    }
    `mv -f $Lib_VersionName.h*.tu temp/`;
	return (split("\n", `find temp -maxdepth 1 -name "$Lib_VersionName\.h*\.tu"`))[0];
}

sub headerFilter($)
{
	my $Destination = $_[0];
    my $FileDescr = `file $Destination`;
    return (($Destination =~ m/\.h\Z/) or ($FileDescr =~ m/:[ ]*ASCII C[\+]* program text/ and $Destination !~ m/(\.cpp|\.c)\Z/));
}

sub getTN($$)
{
	return $TypeDescr{$Version}{$_[0]}{$_[1]}{'Name'};
}

sub getTT($$)
{
	return $TypeDescr{$Version}{$_[0]}{$_[1]}{'Type'};
}

sub getTL($$)
{
	return $TypeDescr{$Version}{$_[0]}{$_[1]}{'Library'};
}

sub interfaceFilter($)
{
	if(($_[0] =~ m/_ZGV/) or
		($_[0] =~ m/__cxxabiv(.*)_type_info/) or
		($_[0] =~ m/_ZTI/) or
		($_[0] =~ m/_ZTS/) or
		($_[0] =~ m/_ZTT/) or
		($_[0] =~ m/_ZTV/) or
		($_[0] =~ m/_ZThn/) or
		($_[0] =~ m/_ZTv0_n/) or
		($_[0] =~ m/_ZNSt12strstreambuf/) or
		($_[0] =~ m/_ZNSt10ostrstream/) or
		($_[0] =~ m/_ZNSt10istrstream/) or
		($_[0] =~ m/_ZNSt9strstream/) or
		($_[0] =~ m/_ZNKSt9strstream/) or
		($_[0] =~ m/_ZNKSt10istrstream/) or
		($_[0] =~ m/_ZNKSt10ostrstream/) or
		($_[0] =~ m/_ZNKSt12strstreambuf/) or
		($_[0] =~ m/__cxa_/) or
		($_[0] =~ m/__dynamic_cast/) or
		($_[0] =~ m/__gxx_personality_v0/))
	{
		return 0;
	}
	else
	{
		return 1;
	}
}

sub parseHeaders_AllInOne()
{
    `mkdir -p header_compile_errors/$TargetLibraryName/`;
    `rm -fr header_compile_errors/$TargetLibraryName/$Descriptor{$Version}{'Version'}`;
	my $DumpPath = getDump_AllInOne();
	if(not $DumpPath)
	{
		print "\nERROR: can't create gcc syntax tree for headers\nyou can see compilation errors in the file header_compile_errors/$TargetLibraryName/$Descriptor{$Version}{'Version'}\n";
		exit(1);
	}
	getInfo($DumpPath);
    `rm -fr temp/*`;
}

sub parseHeader($)
{
	my $Destination = $_[0];
	my $DumpPath = getDump_Separately($Destination);
	if(not $DumpPath)
	{
		print "ERROR: can't create gcc syntax tree for header\nyou can see compilation errors in the file header_compile_errors/$TargetLibraryName/$Descriptor{$Version}{'Version'}\n";
		exit(1);
	}
	getInfo($DumpPath);
    `rm -fr temp/*`;
}

sub prepareInterfaces($)
{
	my $LibVersion = $_[0];
    my @MnglNames = ();
    my @UnMnglNames = ();
    foreach my $FuncInfoId (sort keys(%{$FuncDescr{$LibVersion}}))
    {
        if($FuncDescr{$LibVersion}{$FuncInfoId}{'MnglName'} =~ /\A_Z/)
        {
            push(@MnglNames, $FuncDescr{$LibVersion}{$FuncInfoId}{'MnglName'});
        }
    }
    if($#MnglNames > -1)
    {
        @UnMnglNames = reverse(unmangleArray(@MnglNames));
        foreach my $FuncInfoId (sort keys(%{$FuncDescr{$LibVersion}}))
        {
            if($FuncDescr{$LibVersion}{$FuncInfoId}{'MnglName'} =~ /\A_Z/)
            {
                $FuncDescr{$LibVersion}{$FuncInfoId}{'Name'} = pop(@UnMnglNames);
                $tr_name{$FuncDescr{$LibVersion}{$FuncInfoId}{'MnglName'}} = $FuncDescr{$LibVersion}{$FuncInfoId}{'Name'} if($FuncDescr{$LibVersion}{$FuncInfoId}{'Name'});
                $FuncDescr{$LibVersion}{$FuncInfoId}{'Signature'} = $FuncDescr{$LibVersion}{$FuncInfoId}{'Name'};
            }
        }
    }
    foreach my $FuncInfoId (keys(%{$FuncDescr{$LibVersion}}))
    {
        next if(not $FuncDescr{$LibVersion}{$FuncInfoId}{'Name'});
        next if($FuncDescr{$LibVersion}{$FuncInfoId}{'Library'} ne $TargetLibraryName);
        next if(not $FuncDescr{$LibVersion}{$FuncInfoId}{'MnglName'});
        next if($FuncDescr{$LibVersion}{$FuncInfoId}{'Name'} =~ /\.\_[0-9]/);
        %{$Functions{$LibVersion}{$FuncDescr{$LibVersion}{$FuncInfoId}{'MnglName'}}} = %{$FuncDescr{$LibVersion}{$FuncInfoId}};
    }
}

sub initializeClassVirtFunc($)
{
    my $LibVersion = $_[0];
    foreach my $FuncName (keys(%{$Functions{$LibVersion}}))
    {
        if($Functions{$LibVersion}{$FuncName}{'Virtual'} eq "Yes")
        {
            my $ClassName = $TypeDescr{$LibVersion}{getTypeDeclId_by_Ver($Functions{$LibVersion}{$FuncName}{'Class'}, $LibVersion)}{$Functions{$LibVersion}{$FuncName}{'Class'}}{'Name'};
            $ClassVirtFunc{$LibVersion}{$ClassName}{$FuncName} = 1;
            $ClassIdVirtFunc{$LibVersion}{$Functions{$LibVersion}{$FuncName}{'Class'}}{$FuncName} = 1;
            $ClassId{$LibVersion}{$ClassName} = $Functions{$LibVersion}{$FuncName}{'Class'};
        }
    }
}

sub checkVirtFuncRedefinitions($)
{
    my $LibVersion = $_[0];
    foreach my $Class_Name (keys(%{$ClassVirtFunc{$LibVersion}}))
    {
        foreach my $VirtFuncName (keys(%{$ClassVirtFunc{$LibVersion}{$Class_Name}}))
        {
            $Functions{$LibVersion}{$VirtFuncName}{'VirtualRedefine'} = find_virtual_method_in_base_classes($VirtFuncName, $ClassId{$LibVersion}{$Class_Name}, $LibVersion);
        }
    }
}

sub setVirtFuncPositions($)
{
    my $LibVersion = $_[0];
    foreach my $Class_Name (keys(%{$ClassVirtFunc{$LibVersion}}))
    {
        my $Position = 0;
        foreach my $VirtFuncName (sort {int($Functions{$LibVersion}{$a}{'Line'}) <=> int($Functions{$LibVersion}{$b}{'Line'})} keys(%{$ClassVirtFunc{$LibVersion}{$Class_Name}}))
        {
            if($ClassVirtFunc{1}{$Class_Name}{$VirtFuncName} and $ClassVirtFunc{2}{$Class_Name}{$VirtFuncName} and not $Functions{1}{$VirtFuncName}{'VirtualRedefine'} and not $Functions{2}{$VirtFuncName}{'VirtualRedefine'})
            {
                $Functions{$LibVersion}{$VirtFuncName}{'Position'} = $Position;
                $Position += 1;
            }
        }
    }
}

sub check_VirtualTable($$)
{
    my $TargetFunction = $_[0];
    my $LibVersion = $_[1];
    my $Class_Id = $Functions{$LibVersion}{$TargetFunction}{'Class'};
    my $Class_DId = getTypeDeclId_by_Ver($Class_Id, $LibVersion);
    my %Class_Type = get_Type($Class_DId, $Class_Id, $LibVersion);
    foreach my $VirtFuncName (keys(%{$ClassVirtFunc{2}{$Class_Type{'Name'}}}))
    {#Added
        if($ClassId{1}{$Class_Type{'Name'}} and not $ClassVirtFunc{1}{$Class_Type{'Name'}}{$VirtFuncName})
        {
            if($Functions{2}{$VirtFuncName}{'VirtualRedefine'})
            {
                if($TargetFunction eq $VirtFuncName)
                {
                    my $BaseClass_Id = $Functions{2}{$Functions{2}{$VirtFuncName}{'VirtualRedefine'}}{'Class'};
                    my %BaseClass_Type = get_Type(getTypeDeclId_by_Ver($BaseClass_Id, 2), $BaseClass_Id, 2);
                    my $BaseClass_Name = $BaseClass_Type{'Name'};
                    %{$CompatProblems{$TargetFunction}{"Virtual_Function_Redefinition"}{unmangle($Functions{2}{$VirtFuncName}{'VirtualRedefine'})}}=(
                        "Type_Name"=>$Class_Type{'Name'},
                        "Type_Type"=>$Class_Type{'Type'},
                        "Header"=>$Functions{2}{$TargetFunction}{'Header'},
                        "Line"=>$Functions{2}{$TargetFunction}{'Line'},
                        "Target"=>unmangle($Functions{2}{$VirtFuncName}{'VirtualRedefine'}),
                        "Signature"=>unmangle($TargetFunction),
                        "Old_Value"=>unmangle($Functions{2}{$VirtFuncName}{'VirtualRedefine'}),
                        "New_Value"=>unmangle($TargetFunction),
                        "Old_SoName"=>$LibInt{1}{$TargetFunction},
                        "New_SoName"=>$LibInt{2}{$TargetFunction}  );
                }
            }
            elsif($TargetFunction ne $VirtFuncName)
            {
                %{$CompatProblems{$TargetFunction}{"Added_Virtual_Function"}{unmangle($VirtFuncName)}}=(
                "Type_Name"=>$Class_Type{'Name'},
                "Type_Type"=>$Class_Type{'Type'},
                "Header"=>$Class_Type{'Header'},
                "Line"=>$Class_Type{'Line'},
                "Target"=>unmangle($VirtFuncName),
                "Signature"=>unmangle($TargetFunction),
                "Old_SoName"=>$LibInt{1}{$TargetFunction},
                "New_SoName"=>$LibInt{2}{$TargetFunction}  );
            }
        }
    }
    foreach my $VirtFuncName (keys(%{$ClassVirtFunc{1}{$Class_Type{'Name'}}}))
    {#Withdrawn
        if($ClassId{2}{$Class_Type{'Name'}} and not $ClassVirtFunc{2}{$Class_Type{'Name'}}{$VirtFuncName})
        {
            if($Functions{1}{$VirtFuncName}{'VirtualRedefine'})
            {
                if($TargetFunction eq $VirtFuncName)
                {
                    my $BaseClass_Id = $Functions{1}{$Functions{1}{$VirtFuncName}{'VirtualRedefine'}}{'Class'};
                    my $BaseClass_Name = $TypeDescr{1}{getTypeDeclId_by_Ver($BaseClass_Id, 1)}{$BaseClass_Id}{'Name'};
                    %{$CompatProblems{$TargetFunction}{"Virtual_Function_Redefinition_B"}{unmangle($Functions{1}{$VirtFuncName}{'VirtualRedefine'})}}=(
                        "Type_Name"=>$Class_Type{'Name'},
                        "Type_Type"=>$Class_Type{'Type'},
                        "Header"=>$Functions{2}{$TargetFunction}{'Header'},
                        "Line"=>$Functions{2}{$TargetFunction}{'Line'},
                        "Target"=>unmangle($Functions{1}{$VirtFuncName}{'VirtualRedefine'}),
                        "Signature"=>unmangle($TargetFunction),
                        "Old_Value"=>unmangle($TargetFunction),
                        "New_Value"=>unmangle($Functions{1}{$VirtFuncName}{'VirtualRedefine'}),
                        "Old_SoName"=>$LibInt{1}{$TargetFunction},
                        "New_SoName"=>$LibInt{2}{$TargetFunction}  );
                }
            }
            else
            {
                %{$CompatProblems{$TargetFunction}{"Withdrawn_Virtual_Function"}{unmangle($VirtFuncName)}}=(
                "Type_Name"=>$Class_Type{'Name'},
                "Type_Type"=>$Class_Type{'Type'},
                "Header"=>$Class_Type{'Header'},
                "Line"=>$Class_Type{'Line'},
                "Target"=>unmangle($VirtFuncName),
                "Signature"=>unmangle($TargetFunction),
                "Old_SoName"=>$LibInt{1}{$TargetFunction},
                "New_SoName"=>$LibInt{2}{$TargetFunction}  );
            }
        }
    }
}

sub find_virtual_method_in_base_classes($$$)
{
    my $VirtFuncName = $_[0];
    my $Checked_ClassId = $_[1];
    my $LibVersion = $_[2];
    foreach my $BaseClass_Id (keys(%{$TypeDescr{$LibVersion}{getTypeDeclId_by_Ver($Checked_ClassId, $LibVersion)}{$Checked_ClassId}{'BaseClass'}}))
    {
        my $VirtMethodInClass = find_virtual_method_in_class($VirtFuncName, $BaseClass_Id, $LibVersion);
        if($VirtMethodInClass)
        {
            return $VirtMethodInClass;
        }
        my $VirtMethodInBaseClasses = find_virtual_method_in_base_classes($VirtFuncName, $BaseClass_Id, $LibVersion);
        if($VirtMethodInBaseClasses)
        {
            return $VirtMethodInBaseClasses;
        }
    }
    return "";
}

sub find_virtual_method_in_class($$$)
{
    my $VirtFuncName = $_[0];
    my $Checked_ClassId = $_[1];
    my $LibVersion = $_[2];
    foreach my $Checked_VirtFuncName (keys(%{$ClassIdVirtFunc{$LibVersion}{$Checked_ClassId}}))
    {
        if(haveSameSignatures($VirtFuncName, $Checked_VirtFuncName))
        {
            return $Checked_VirtFuncName;
        }
    }
    return "";
}

sub haveSameSignatures($$)
{
    my $FuncName = $_[0];
    my $FuncName_Checked = $_[1];
    my $ClassName = $TypeDescr{2}{getTypeDeclId_by_Ver($Functions{2}{$FuncName}{'Class'}, 2)}{$Functions{2}{$FuncName}{'Class'}}{'Name'};
    my $ClassName_Checked = $TypeDescr{1}{getTypeDeclId_by_Ver($Functions{1}{$FuncName_Checked}{'Class'}, 1)}{$Functions{1}{$FuncName_Checked}{'Class'}}{'Name'};
    return (getFuncSuffix($ClassName, $FuncName) eq getFuncSuffix($ClassName_Checked, $FuncName_Checked));
}

sub getFuncSuffix($$)
{
    my $ClassName = $_[0];
    my $FuncName = $_[1];
    my $Prefix = length($ClassName).$ClassName;
    $FuncName =~ s/_ZN$Prefix//g;
    $FuncName =~ s/_ZNK$Prefix//g;
    return $FuncName;
}

sub isRecurType($$$$)
{
	foreach (@RecurTypes)
	{
		if($_->{'Tid1'} eq $_[0] and $_->{'TDid1'} eq $_[1] and $_->{'Tid2'} eq $_[2] and $_->{'TDid2'} eq $_[3])
		{
			return 1;
		}
	}
	return 0;
}

sub find_MemberPair_Pos_byName($$)
{
    my $Member_Name = $_[0];
    my $Pair_Type = $_[1];
    foreach my $MemberPair_Pos (sort keys(%{$Pair_Type->{'Memb'}}))
    {
        if($Pair_Type->{'Memb'}{$MemberPair_Pos}{'name'} eq $Member_Name)
        {
            return $MemberPair_Pos;
        }
    }
    return "lost";
}

sub getBitfieldSum($$)
{
    my $Member_Pos = $_[0];
    my $Pair_Type = $_[1];
    my $BitfieldSum = 0;
    while($Member_Pos>-1)
    {
        return $BitfieldSum if(not $Pair_Type->{'Memb'}{$Member_Pos}{'bitfield'});
        $BitfieldSum += $Pair_Type->{'Memb'}{$Member_Pos}{'bitfield'};
        $Member_Pos -= 1;
    }
    return $BitfieldSum;
}

sub find_MemberPair_Pos_byVal($$)
{
    my $Member_Value = $_[0];
    my $Pair_Type = $_[1];
    foreach my $MemberPair_Pos (sort keys(%{$Pair_Type->{'Memb'}}))
    {
        if($Pair_Type->{'Memb'}{$MemberPair_Pos}{'value'} eq $Member_Value)
        {
            return $MemberPair_Pos;
        }
    }
    return "lost";
}

my %AnonParentType;

sub getAnonParentName($$$)
{
    my $TypeDeclId = $_[0];
    my $TypeId = $_[1];
    my $LibVersion = $_[2];
    my $Parent_TypeDeclId = $AnonParentType{$LibVersion}{$TypeDeclId}{$TypeId}{'TDid'};
    my $Parent_TypeId = $AnonParentType{$LibVersion}{$TypeDeclId}{$TypeId}{'Tid'};
    return %{$TypeDescr{$LibVersion}{$Parent_TypeDeclId}{$Parent_TypeId}};
}

my %Priority_Value=(
"High"=>3,
"Medium"=>2,
"Low"=>1
);

sub max_priority($$)
{
    my $Priority1 = $_[0];
    my $Priority2 = $_[1];
    if($Priority_Value{$Priority1}>=$Priority_Value{$Priority1})
    {
        return $Priority1;
    }
    else
    {
        return $Priority2;
    }
}

sub set_Problems_Priority()
{
    foreach my $InterfaceName (sort keys(%CompatProblems))
    {
        foreach my $Kind (sort keys(%{$CompatProblems{$InterfaceName}}))
        {
            foreach my $Location (sort keys(%{$CompatProblems{$InterfaceName}{$Kind}}))
            {
                my $IsInTypeInternals = $CompatProblems{$InterfaceName}{$Kind}{$Location}{'IsInTypeInternals'};
                my $InitialType_Type = $CompatProblems{$InterfaceName}{$Kind}{$Location}{'InitialType_Type'};
                if($Kind eq "Function_Become_Static")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "High";
                }
                elsif($Kind eq "Function_Become_NonStatic")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "High";
                }
                elsif($Kind eq "Parameter_Type_And_Size")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "High";
                }
                elsif($Kind eq "Parameter_Type")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Low";
                }
                elsif($Kind eq "Parameter_BaseType")
                {
                    if($InitialType_Type eq "Pointer")
                    {
                        $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Low";
                    }
                    else
                    {
                        $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "High";
                    }
                }
                elsif($Kind eq "Parameter_PointerLevel_And_Size")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "High";
                }
                elsif($Kind eq "Parameter_PointerLevel")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "High";
                }
                elsif($Kind eq "Return_Type_And_Size")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Medium";
                }
                elsif($Kind eq "Return_Type")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Low";
                }
                elsif($Kind eq "Return_BaseType")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Medium";
                }
                elsif($Kind eq "Return_PointerLevel_And_Size")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Medium";
                }
                elsif($Kind eq "Return_PointerLevel")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Low";
                }
                if($Kind eq "Added_Virtual_Function")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "High";
                }
                elsif($Kind eq "Withdrawn_Virtual_Function")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "High";
                }
                elsif($Kind eq "Virtual_Function_Position")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "High";
                }
                elsif($Kind eq "Virtual_Function_Redefinition")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Low";
                }
                elsif($Kind eq "Virtual_Function_Redefinition_B")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Low";
                }
                elsif($Kind eq "Size")
                {
                    if(($InitialType_Type eq "Pointer") or ($InitialType_Type eq "Array"))
                    {
                        $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Low";
                    }
                    else
                    {
                        if($IsInTypeInternals)
                        {
                            $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Medium";
                        }
                        else
                        {
                            $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "High";
                        }
                    }
                }
                elsif($Kind eq "Added_Member")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Low";
                }
                elsif($Kind eq "Added_Middle_Member")
                {
                    if($IsInTypeInternals)
                    {
                        $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Medium";
                    }
                    else
                    {
                        $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "High";
                    }
                }
                elsif($Kind eq "Withdrawn_Member_And_Size")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Medium";
                }
                elsif($Kind eq "Withdrawn_Member")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Low";
                }
                elsif($Kind eq "Withdrawn_Middle_Member_And_Size")
                {
                    if($IsInTypeInternals)
                    {
                        $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Medium";
                    }
                    else
                    {
                        $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "High";
                    }
                }
                elsif($Kind eq "Withdrawn_Middle_Member")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Medium";
                }
                elsif($Kind eq "Member_Rename")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Low";
                }
                elsif($Kind eq "Enum_Member_Value")
                {
                    if($IsInTypeInternals)
                    {
                        $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Medium";
                    }
                    else
                    {
                        $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "High";
                    }
                }
                elsif($Kind eq "Enum_Member_Name")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Low";
                }
                elsif($Kind eq "Member_Type_And_Size")
                {
                    if(($InitialType_Type eq "Pointer") or ($InitialType_Type eq "Array"))
                    {
                        $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Low";
                    }
                    else
                    {
                        if($IsInTypeInternals)
                        {
                            $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Low";
                        }
                        else
                        {
                            $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "High";
                        }
                    }
                }
                elsif($Kind eq "Member_Type")
                {
                    $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Low";
                }
                elsif($Kind eq "Member_BaseType")
                {
                    if(($InitialType_Type eq "Pointer") or ($InitialType_Type eq "Array"))
                    {
                        $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Low";
                    }
                    else
                    {
                        if($IsInTypeInternals)
                        {
                            $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Low";
                        }
                        else
                        {
                            $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "High";
                        }
                    }
                }
                elsif($Kind eq "Member_PointerLevel_And_Size")
                {
                    if(($InitialType_Type eq "Pointer") or ($InitialType_Type eq "Array"))
                    {
                        $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Low";
                    }
                    else
                    {
                        if($IsInTypeInternals)
                        {
                            $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Low";
                        }
                        else
                        {
                            $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Medium";
                        }
                    }
                }
                elsif($Kind eq "Member_PointerLevel")
                {
                    if(($InitialType_Type eq "Pointer") or ($InitialType_Type eq "Array"))
                    {
                        $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Low";
                    }
                    else
                    {
                        if($IsInTypeInternals)
                        {
                            $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Low";
                        }
                        else
                        {
                            $CompatProblems{$InterfaceName}{$Kind}{$Location}{'Priority'} = "Medium";
                        }
                    }
                }
            }
        }
    }
}

sub pushType($$$$)
{
    my %TypeDescriptor=(
        "Tid1"  => $_[0],
        "TDid1" => $_[1],
        "Tid2"  => $_[2],
        "TDid2" => $_[3]  );
    push(@RecurTypes, \%TypeDescriptor);
}

sub mergeTypes($$$$)
{
    my $Type1_Id = $_[0];
    my $Type1_DId = $_[1];
    my $Type2_Id = $_[2];
    my $Type2_DId = $_[3];
    my %Sub_SubProblems = ();
    my %SubProblems = ();
    if((not $Type1_Id and not $Type1_DId) or (not $Type2_Id and not $Type2_DId))
    {#Not Empty Inputs Only
        return ();
    }
    if($Cache{'mergeTypes'}{$Type1_Id}{$Type1_DId}{$Type2_Id}{$Type2_DId})
    {#Already Merged
        return %{$Cache{'mergeTypes'}{$Type1_Id}{$Type1_DId}{$Type2_Id}{$Type2_DId}};
    }
    my %Type1 = get_Type($Type1_DId, $Type1_Id, 1);
    my %Type2 = get_Type($Type2_DId, $Type2_Id, 2);
	my %Type1_Pure = get_PureType($Type1_DId, $Type1_Id, 1);
    my %Type2_Pure = get_PureType($Type2_DId, $Type2_Id, 2);
    if(isRecurType($Type1_Pure{'Tid'}, $Type1_Pure{'TDid'}, $Type2_Pure{'Tid'}, $Type2_Pure{'TDid'}))
    {#Recursive Declarations
        return ();
    }
    if(isAnon($Type1_Pure{'Name'}))
    {
        my %AnonParentType1_Pure = getAnonParentName($Type1_Pure{'TDid'}, $Type1_Pure{'Tid'}, 1);
        if($AnonParentType1_Pure{'Type'} eq "Typedef")
        {
            $Type1_Pure{'Name'} = $AnonParentType1_Pure{'Name'};
        }
    }
    if(isAnon($Type2_Pure{'Name'}))
    {
        my %AnonParentType2_Pure = getAnonParentName($Type2_Pure{'TDid'}, $Type2_Pure{'Tid'}, 2);
        if($AnonParentType2_Pure{'Type'} eq "Typedef")
        {
            $Type2_Pure{'Name'} = $AnonParentType2_Pure{'Name'};
        }
    }
    return if(not $Type1_Pure{'Name'} or not $Type2_Pure{'Name'});
    return if($OpaqueTypes{$Type1_Pure{'Name'}});
    if(($Type1_Pure{'Name'} ne $Type2_Pure{'Name'}) and ($Type1_Pure{'Type'} ne "Pointer"))
    {#Different types
        return ();
    }
	pushType($Type1_Pure{'Tid'}, $Type1_Pure{'TDid'}, $Type2_Pure{'Tid'}, $Type2_Pure{'TDid'});
	if($Type1_Pure{'Size'} and $Type2_Pure{'Size'} and ($Type1_Pure{'Name'} eq $Type2_Pure{'Name'}) and ($Type1_Pure{'Type'} eq "Struct" or $Type1_Pure{'Type'} eq "Class"))
	{#Check Size
		if($Type1_Pure{'Size'} ne $Type2_Pure{'Size'})
		{
            %{$SubProblems{"Size"}{$Type1_Pure{'Name'}}}=(
                "Type_Name"=>$Type1_Pure{'Name'},
                "Type_Type"=>$Type1_Pure{'Type'},
                "Header"=>$Type2_Pure{'Header'},
                "Line"=>$Type2_Pure{'Line'},
                "Old_Value"=>$Type1_Pure{'Size'},
                "New_Value"=>$Type2_Pure{'Size'}  );
		}
	}
    if($Type1_Pure{'Name'} and $Type2_Pure{'Name'} and ($Type1_Pure{'Name'} ne $Type2_Pure{'Name'}) and ($Type1_Pure{'Name'} !~ /\Avoid[ ]*\*/) and ($Type2_Pure{'Name'} =~ /\Avoid[ ]*\*/))
    {#Check "void *"
        pop(@RecurTypes);
        return ();
    }
	if($Type1_Pure{'BaseType'}{'Tid'} and $Type2_Pure{'BaseType'}{'Tid'})
	{#Check Base Types
		%Sub_SubProblems = &mergeTypes($Type1_Pure{'BaseType'}{'Tid'}, $Type1_Pure{'BaseType'}{'TDid'}, $Type2_Pure{'BaseType'}{'Tid'}, $Type2_Pure{'BaseType'}{'TDid'});
        foreach my $Sub_SubProblemType (keys(%Sub_SubProblems))
        {
            foreach my $Sub_SubLocation (keys(%{$Sub_SubProblems{$Sub_SubProblemType}}))
            {
                %{$SubProblems{$Sub_SubProblemType}{$Sub_SubLocation}} = %{$Sub_SubProblems{$Sub_SubProblemType}{$Sub_SubLocation}};
                $SubProblems{$Sub_SubProblemType}{$Sub_SubLocation}{'InitialType_Type'} = $Type1_Pure{'Type'};
            }
        }
	}
    foreach my $Member_Pos (sort keys(%{$Type1_Pure{'Memb'}}))
    {#Check Members
        next if($Type1_Pure{'Memb'}{$Member_Pos}{'access'} eq "private");
        my $Member_Name = $Type1_Pure{'Memb'}{$Member_Pos}{'name'};
        next if(not $Member_Name);
        my $Member_Target = $Member_Name;
        my $Member_Location = $Member_Name;
        my $MemberPair_Pos = find_MemberPair_Pos_byName($Member_Name, \%Type2_Pure);
        if(($MemberPair_Pos eq "lost") and (($Type2_Pure{'Type'} eq "Struct") or ($Type2_Pure{'Type'} eq "Class")))
        {#Withdrawn_Member
            if($Member_Pos > keys(%{$Type2_Pure{'Memb'}}) - 1)
            {
                if($Type1_Pure{'Size'} ne $Type2_Pure{'Size'})
                {
                    %{$SubProblems{"Withdrawn_Member_And_Size"}{$Member_Target}}=(
                        "Target"=>$Member_Target,
                        "Type_Name"=>$Type1_Pure{'Name'},
                        "Type_Type"=>$Type1_Pure{'Type'},
                        "Header"=>$Type2_Pure{'Header'},
                        "Line"=>$Type2_Pure{'Line'},
                        "Old_Size"=>$Type1_Pure{'Size'},
                        "New_Size"=>$Type2_Pure{'Size'}  );
                }
                else
                {
                    %{$SubProblems{"Withdrawn_Member"}{$Member_Target}}=(
                        "Target"=>$Member_Target,
                        "Type_Name"=>$Type1_Pure{'Name'},
                        "Type_Type"=>$Type1_Pure{'Type'},
                        "Header"=>$Type2_Pure{'Header'},
                        "Line"=>$Type2_Pure{'Line'}  );
                }
                next;
            }
            elsif($Member_Pos < keys(%{$Type1_Pure{'Memb'}}) - 1)
            {
                my $MemberType_Id = $Type1_Pure{'Memb'}{$Member_Pos}{'type'};
                my $MemberType_DId = getTypeDeclId_by_Ver($MemberType_Id, 1);
                my %MemberType_Pure = get_PureType($MemberType_DId, $MemberType_Id, 1);
                
                my $MemberStraightPairType_Id = $Type2_Pure{'Memb'}{$Member_Pos}{'type'};
                my $MemberStraightPairType_DId = getTypeDeclId_by_Ver($MemberStraightPairType_Id, 2);
                my %MemberStraightPairType_Pure = get_PureType($MemberStraightPairType_DId, $MemberStraightPairType_Id, 2);
                
                if(($MemberType_Pure{'Size'} eq $MemberStraightPairType_Pure{'Size'}) and find_MemberPair_Pos_byName($Type2_Pure{'Memb'}{$Member_Pos}{'name'}, \%Type1_Pure) eq "lost")
                {
                    %{$SubProblems{"Member_Rename"}{$Member_Target}}=(
                        "Target"=>$Member_Target,
                        "Type_Name"=>$Type1_Pure{'Name'},
                        "Type_Type"=>$Type1_Pure{'Type'},
                        "Header"=>$Type2_Pure{'Header'},
                        "Line"=>$Type2_Pure{'Line'},
                        "Old_Value"=>$Type1_Pure{'Memb'}{$Member_Pos}{'name'},
                        "New_Value"=>$Type2_Pure{'Memb'}{$Member_Pos}{'name'}  );
                    $MemberPair_Pos = $Member_Pos;
                }
                else
                {
                    if($Type1_Pure{'Memb'}{$Member_Pos}{'bitfield'})
                    {
                        my $BitfieldSum = getBitfieldSum($Member_Pos-1, \%Type1_Pure)%($PointerSize*8);
                        if($BitfieldSum and $BitfieldSum-$Type2_Pure{'Memb'}{$Member_Pos}{'bitfield'}>=0)
                        {
                            %{$SubProblems{"Withdrawn_Middle_Member"}{$Member_Target}}=(
                            "Target"=>$Member_Target,
                            "Type_Name"=>$Type1_Pure{'Name'},
                            "Type_Type"=>$Type1_Pure{'Type'},
                            "Header"=>$Type2_Pure{'Header'},
                            "Line"=>$Type2_Pure{'Line'}  );
                            next;
                        }
                    }
                    %{$SubProblems{"Withdrawn_Middle_Member_And_Size"}{$Member_Target}}=(
                        "Target"=>$Member_Target,
                        "Type_Name"=>$Type1_Pure{'Name'},
                        "Type_Type"=>$Type1_Pure{'Type'},
                        "Header"=>$Type2_Pure{'Header'},
                        "Line"=>$Type2_Pure{'Line'}  );
                    next;
                }
            }
        }
        my $MemberType1_Id = $Type1_Pure{'Memb'}{$Member_Pos}{'type'};
        my $MemberType1_DId = getTypeDeclId_by_Ver($MemberType1_Id, 1);
        my $MemberType2_Id = $Type2_Pure{'Memb'}{$MemberPair_Pos}{'type'};
        my $MemberType2_DId = getTypeDeclId_by_Ver($MemberType2_Id, 2);
        my %MemberType1 = get_Type($MemberType1_DId, $MemberType1_Id, 1);
        my %MemberType2 = get_Type($MemberType2_DId, $MemberType2_Id, 2);
        my %MemberType1_Pure = get_PureType($MemberType1_DId, $MemberType1_Id, 1);
        my %MemberType2_Pure = get_PureType($MemberType2_DId, $MemberType2_Id, 2);
        my %MemberType1_Base = get_BaseType($MemberType1_DId, $MemberType1_Id, 1);
        my %MemberType2_Base = get_BaseType($MemberType2_DId, $MemberType2_Id, 2);
        my $MemberType1_PointerLevel = get_PointerLevel($MemberType1_DId, $MemberType1_Id, 1);
        my $MemberType2_PointerLevel = get_PointerLevel($MemberType2_DId, $MemberType2_Id, 2);
        
        if($Type1_Pure{'Type'} eq "Enum")
        {#Enum_Member_Value
            my $Member_Value1 = $Type1_Pure{'Memb'}{$Member_Pos}{'value'};
            next if(not $Member_Name or not $Member_Value1);
            my $Member_Value2 = $Type2_Pure{'Memb'}{$MemberPair_Pos}{'value'};
            if($MemberPair_Pos eq "lost")
            {
                $MemberPair_Pos = find_MemberPair_Pos_byVal($Member_Value1, \%Type2_Pure);
                if($MemberPair_Pos ne "lost")
                {
                    %{$SubProblems{"Enum_Member_Name"}{$Type1_Pure{'Memb'}{$Member_Pos}{'value'}}}=(
                        "Target"=>$Type1_Pure{'Memb'}{$Member_Pos}{'value'},
                        "Type_Name"=>$Type1_Pure{'Name'},
                        "Type_Type"=>"Enum",
                        "Header"=>$Type2_Pure{'Header'},
                        "Line"=>$Type2_Pure{'Line'},
                        "Old_Value"=>$Type1_Pure{'Memb'}{$Member_Pos}{'name'},
                        "New_Value"=>$Type2_Pure{'Memb'}{$MemberPair_Pos}{'name'}  );
                }
            }
            else
            {
                if($Member_Value1 ne "" and $Member_Value2 ne "")
                {
                    if($Member_Value1 ne $Member_Value2)
                    {
                        %{$SubProblems{"Enum_Member_Value"}{$Member_Target}}=(
                            "Target"=>$Member_Target,
                            "Type_Name"=>$Type1_Pure{'Name'},
                            "Type_Type"=>"Enum",
                            "Header"=>$Type2_Pure{'Header'},
                            "Line"=>$Type2_Pure{'Line'},
                            "Old_Value"=>$Type1_Pure{'Memb'}{$Member_Pos}{'value'},
                            "New_Value"=>$Type2_Pure{'Memb'}{$MemberPair_Pos}{'value'}  );
                    }
                }
            }
            next;
        }
        if($MemberType1{'Type'} eq "Array")
        {
            if($MemberType1{'Name'} ne $MemberType2{'Name'})
            {
                if($MemberType1{'Size'} and $MemberType2{'Size'} and ($MemberType1{'Size'} ne $MemberType2{'Size'}))
                {
                    %{$SubProblems{"Member_Type_And_Size"}{$Member_Target}}=(
                        "Target"=>$Member_Target,
                        "Type_Name"=>$Type1_Pure{'Name'},
                        "Type_Type"=>$Type1_Pure{'Type'},
                        "Header"=>$Type2_Pure{'Header'},
                        "Line"=>$Type2_Pure{'Line'},
                        "Old_Value"=>$MemberType1{'Name'},
                        "New_Value"=>$MemberType2{'Name'},
                        "Old_Size"=>$MemberType1{'Size'}*$MemberType1_Base{'Size'},
                        "New_Size"=>$MemberType2{'Size'}*$MemberType2_Base{'Size'},
                        "InitialType_Type"=>"Array"  );
                }
            }
        }
        if($MemberType1_Base{'Name'} and $MemberType2_Base{'Name'} and ($MemberType1_Base{'Name'} ne $MemberType2_Base{'Name'}) and ($MemberType1{'Name'} ne $MemberType2{'Name'}))
        {#Member type or base type
            if($MemberType1_Base{'Size'} and $MemberType2_Base{'Size'} and ($MemberType1_Base{'Size'} ne $MemberType2_Base{'Size'}))
            {
                if($MemberType1_Base{'Name'} eq $MemberType1{'Name'})
                {
                    if($MemberType1_Pure{'Size'} and $MemberType2_Pure{'Size'} and ($MemberType1_Pure{'Size'} ne $MemberType2_Pure{'Size'}))
                    {
                        %{$SubProblems{"Member_Type_And_Size"}{$Member_Target}}=(
                            "Target"=>$Member_Target,
                            "Type_Name"=>$Type1_Pure{'Name'},
                            "Type_Type"=>$Type1_Pure{'Type'},
                            "Header"=>$Type2_Pure{'Header'},
                            "Line"=>$Type2_Pure{'Line'},
                            "Old_Value"=>$MemberType1{'Name'},
                            "New_Value"=>$MemberType2{'Name'},
                            "Old_Size"=>$MemberType1{'Size'},
                            "New_Size"=>$MemberType2{'Size'},
                            "InitialType_Type"=>$MemberType1_Pure{'Type'}  );
                    }
                    else
                    {
                        %{$SubProblems{"Member_Type"}{$Member_Target}}=(
                            "Target"=>$Member_Target,
                            "Type_Name"=>$Type1_Pure{'Name'},
                            "Type_Type"=>$Type1_Pure{'Type'},
                            "Header"=>$Type2_Pure{'Header'},
                            "Line"=>$Type2_Pure{'Line'},
                            "Old_Value"=>$MemberType1{'Name'},
                            "New_Value"=>$MemberType2{'Name'},
                            "InitialType_Type"=>$MemberType1_Pure{'Type'}  );
                    }
                }
                else
                {
                    %{$SubProblems{"Member_BaseType"}{$Member_Target}}=(
                        "Target"=>$Member_Target,
                        "Type_Name"=>$Type1_Pure{'Name'},
                        "Type_Type"=>$Type1_Pure{'Type'},
                        "Header"=>$Type2_Pure{'Header'},
                        "Line"=>$Type2_Pure{'Line'},
                        "Old_Value"=>$MemberType1_Base{'Name'},
                        "New_Value"=>$MemberType2_Base{'Name'},
                        "Old_Size"=>$MemberType1_Base{'Size'},
                        "New_Size"=>$MemberType2_Base{'Size'},
                        "InitialType_Type"=>$MemberType1_Pure{'Type'}  );
                }
            }
            elsif($MemberType1_Base{'Size'} and $MemberType2_Base{'Size'} and $MemberType1_Pure{'Size'} eq $MemberType2_Pure{'Size'})
            {
                %{$SubProblems{"Member_Type"}{$Member_Target}}=(
                    "Target"=>$Member_Target,
                    "Type_Name"=>$Type1_Pure{'Name'},
                    "Type_Type"=>$Type1_Pure{'Type'},
                    "Header"=>$Type2_Pure{'Header'},
                    "Line"=>$Type2_Pure{'Line'},
                    "Old_Value"=>$MemberType1{'Name'},
                    "New_Value"=>$MemberType2{'Name'},
                    "InitialType_Type"=>$MemberType1_Pure{'Type'}  );
            }
        }
        if(($MemberType1_PointerLevel ne "") and ($MemberType2_PointerLevel ne "") and ($MemberType1_PointerLevel ne $MemberType2_PointerLevel))
        {#Member pointer level
            if($MemberType1_Pure{'Size'} and $MemberType2_Pure{'Size'} and ($MemberType1_Pure{'Size'} ne $MemberType2_Pure{'Size'}))
            {
                %{$SubProblems{"Member_PointerLevel_And_Size"}{$Member_Target}}=(
                    "Target"=>$Member_Target,
                    "Type_Name"=>$Type1_Pure{'Name'},
                    "Type_Type"=>$Type1_Pure{'Type'},
                    "Header"=>$Type2_Pure{'Header'},
                    "Line"=>$Type2_Pure{'Line'},
                    "Old_Value"=>$MemberType1_PointerLevel,
                    "New_Value"=>$MemberType2_PointerLevel,
                    "Old_Size"=>$MemberType1_Pure{'Size'},
                    "New_Size"=>$MemberType2_Pure{'Size'}  );
            }
            else
            {
                %{$SubProblems{"Member_PointerLevel"}{$Member_Target}}=(
                    "Target"=>$Member_Target,
                    "Type_Name"=>$Type1_Pure{'Name'},
                    "Type_Type"=>$Type1_Pure{'Type'},
                    "Header"=>$Type2_Pure{'Header'},
                    "Line"=>$Type2_Pure{'Line'},
                    "Old_Value"=>$MemberType1_PointerLevel,
                    "New_Value"=>$MemberType2_PointerLevel  );
            }
        }
        if($MemberType1_Id and $MemberType2_Id)
        {#Check member types
            %Sub_SubProblems = &mergeTypes($MemberType1_Id, $MemberType1_DId, $MemberType2_Id, $MemberType2_DId);
            foreach my $Sub_SubProblemType (keys(%Sub_SubProblems))
            {
                foreach my $Sub_SubLocation (keys(%{$Sub_SubProblems{$Sub_SubProblemType}}))
                {
                    my $NewLocation = $Member_Location;
                    if($Sub_SubLocation and $NewLocation)
                    {
                        $NewLocation .= "->".$Sub_SubLocation;
                    }
                    %{$SubProblems{$Sub_SubProblemType}{$NewLocation}} = %{$Sub_SubProblems{$Sub_SubProblemType}{$Sub_SubLocation}};
                    $SubProblems{$Sub_SubProblemType}{$NewLocation}{'IsInTypeInternals'} = "Yes";
                    if($Sub_SubLocation !~ /\-\>/)
                    {
                        $SubProblems{$Sub_SubProblemType}{$NewLocation}{'Member_Type_Name'} = $MemberType1{'Name'};
                        $SubProblems{$Sub_SubProblemType}{$NewLocation}{'Start_Type_Name'} = $MemberType1{'Name'};
                    }
                }
            }
        }
    }
                        
    if(($Type2_Pure{'Type'} eq "Struct") or ($Type2_Pure{'Type'} eq "Class"))
    {
        foreach my $Member_Pos (sort keys(%{$Type2_Pure{'Memb'}}))
        {#Check Added Members
            next if(not $Type2_Pure{'Memb'}{$Member_Pos}{'name'});
            my $MemberPair_Pos = find_MemberPair_Pos_byName($Type2_Pure{'Memb'}{$Member_Pos}{'name'}, \%Type1_Pure);
            if($MemberPair_Pos eq "lost")
            {#Added_Member
                if($Member_Pos > keys(%{$Type1_Pure{'Memb'}}) - 1)
                {
                    if($Type1_Pure{'Size'} ne $Type2_Pure{'Size'})
                    {
                        if($Type2_Pure{'Memb'}{$Member_Pos}{'bitfield'})
                        {
                            my $BitfieldSum = getBitfieldSum($Member_Pos-1, \%Type2_Pure)%($PointerSize*8);
                            next if($BitfieldSum and $BitfieldSum<=$PointerSize*8-$Type2_Pure{'Memb'}{$Member_Pos}{'bitfield'});
                        }
                        %{$SubProblems{"Added_Member"}{$Type2_Pure{'Memb'}{$Member_Pos}{'name'}}}=(
                            "Target"=>$Type2_Pure{'Memb'}{$Member_Pos}{'name'},
                            "Type_Name"=>$Type1_Pure{'Name'},
                            "Type_Type"=>$Type1_Pure{'Type'},
                            "Header"=>$Type2_Pure{'Header'},
                            "Line"=>$Type2_Pure{'Line'}  );
                    }
                }
                else
                {
                    my $MemberType_Id = $Type2_Pure{'Memb'}{$Member_Pos}{'type'};
                    my $MemberType_DId = getTypeDeclId_by_Ver($MemberType_Id, 2);
                    my %MemberType_Pure = get_PureType($MemberType_DId, $MemberType_Id, 2);
                    
                    my $MemberStraightPairType_Id = $Type1_Pure{'Memb'}{$Member_Pos}{'type'};
                    my $MemberStraightPairType_DId = getTypeDeclId_by_Ver($MemberStraightPairType_Id, 1);
                    my %MemberStraightPairType_Pure = get_PureType($MemberStraightPairType_DId, $MemberStraightPairType_Id, 1);
                    
                    if(($MemberType_Pure{'Size'} eq $MemberStraightPairType_Pure{'Size'}) and find_MemberPair_Pos_byName($Type1_Pure{'Memb'}{$Member_Pos}{'name'}, \%Type2_Pure) eq "lost")
                    {
                        next if($Type1_Pure{'Memb'}{$Member_Pos}{'access'} eq "private");
                        %{$SubProblems{"Member_Rename"}{$Type2_Pure{'Memb'}{$Member_Pos}{'name'}}}=(
                            "Target"=>$Type1_Pure{'Memb'}{$Member_Pos}{'name'},
                            "Type_Name"=>$Type1_Pure{'Name'},
                            "Type_Type"=>$Type1_Pure{'Type'},
                            "Header"=>$Type2_Pure{'Header'},
                            "Line"=>$Type2_Pure{'Line'},
                            "Old_Value"=>$Type1_Pure{'Memb'}{$Member_Pos}{'name'},
                            "New_Value"=>$Type2_Pure{'Memb'}{$Member_Pos}{'name'}  );
                    }
                    else
                    {
                        if($Type1_Pure{'Size'} ne $Type2_Pure{'Size'})
                        {
                            if($Type2_Pure{'Memb'}{$Member_Pos}{'bitfield'})
                            {
                                my $BitfieldSum = getBitfieldSum($Member_Pos-1, \%Type2_Pure)%($PointerSize*8);
                                next if($BitfieldSum and $BitfieldSum<=$PointerSize*8-$Type2_Pure{'Memb'}{$Member_Pos}{'bitfield'});
                            }
                            %{$SubProblems{"Added_Middle_Member"}{$Type2_Pure{'Memb'}{$Member_Pos}{'name'}}}=(
                                "Target"=>$Type2_Pure{'Memb'}{$Member_Pos}{'name'},
                                "Type_Name"=>$Type1_Pure{'Name'},
                                "Type_Type"=>$Type1_Pure{'Type'},
                                "Header"=>$Type2_Pure{'Header'},
                                "Line"=>$Type2_Pure{'Line'}  );
                        }
                    }
                }
            }
        }
    }
    %{$Cache{'mergeTypes'}{$Type1_Id}{$Type1_DId}{$Type2_Id}{$Type2_DId}} = %SubProblems;
	pop(@RecurTypes);
    return %SubProblems;
}

sub goToFirst($$$$)
{
    my $TypeDId = $_[0];
    my $TypeId = $_[1];
    my $LibVersion = $_[2];
    my $Type_Type = $_[3];
    if(defined $Cache{'goToFirst'}{$TypeDId}{$TypeId}{$LibVersion}{$Type_Type})
    {
        return %{$Cache{'goToFirst'}{$TypeDId}{$TypeId}{$LibVersion}{$Type_Type}};
    }
    my %Type = %{$TypeDescr{$LibVersion}{$TypeDId}{$TypeId}};
    return () if(not $Type{'Type'});
    if($Type{'Type'} ne $Type_Type)
    {
        return () if(not $Type{'BaseType'}{'TDid'} and not $Type{'BaseType'}{'Tid'});
        %Type = goToFirst($Type{'BaseType'}{'TDid'}, $Type{'BaseType'}{'Tid'}, $LibVersion, $Type_Type);
    }
    %{$Cache{'goToFirst'}{$TypeDId}{$TypeId}{$LibVersion}{$Type_Type}} = %Type;
    return %Type;
}

my %TypeSpecAttributes = (
    "Ref" => 1,
    "Const" => 1,
    "Volatile" => 1,
    "Restrict" => 1,
    "Typedef" => 1
);

sub get_PureType($$$)
{
    my $TypeDId = $_[0];
    my $TypeId = $_[1];
    my $LibVersion = $_[2];
    if(defined $Cache{'get_PureType'}{$TypeDId}{$TypeId}{$LibVersion})
    {
        return %{$Cache{'get_PureType'}{$TypeDId}{$TypeId}{$LibVersion}};
    }
    my %Type = %{$TypeDescr{$LibVersion}{$TypeDId}{$TypeId}};
    return %Type if(not $Type{'BaseType'}{'TDid'} and not $Type{'BaseType'}{'Tid'});
    $AnonParentType{$LibVersion}{$Type{'BaseType'}{'TDid'}}{$Type{'BaseType'}{'Tid'}}{'TDid'} = $TypeDId;
    $AnonParentType{$LibVersion}{$Type{'BaseType'}{'TDid'}}{$Type{'BaseType'}{'Tid'}}{'Tid'} = $TypeId;
    if($TypeSpecAttributes{$Type{'Type'}})
    {
        %Type = get_PureType($Type{'BaseType'}{'TDid'}, $Type{'BaseType'}{'Tid'}, $LibVersion);
    }
    %{$Cache{'get_PureType'}{$TypeDId}{$TypeId}{$LibVersion}} = %Type;
    return %Type;
}

sub get_PointerLevel($$$)
{
    my $TypeDId = $_[0];
    my $TypeId = $_[1];
    my $LibVersion = $_[2];
    if(defined $Cache{'get_PointerLevel'}{$TypeDId}{$TypeId}{$LibVersion})
    {
        return $Cache{'get_PointerLevel'}{$TypeDId}{$TypeId}{$LibVersion};
    }
    my %Type = %{$TypeDescr{$LibVersion}{$TypeDId}{$TypeId}};
    return 0 if(not $Type{'BaseType'}{'TDid'} and not $Type{'BaseType'}{'Tid'});
    my $PointerLevel = 0;
    if($Type{'Type'} eq "Pointer")
    {
        $PointerLevel += 1;
    }
    $PointerLevel += get_PointerLevel($Type{'BaseType'}{'TDid'}, $Type{'BaseType'}{'Tid'}, $LibVersion);
    $Cache{'get_PointerLevel'}{$TypeDId}{$TypeId}{$LibVersion} = $PointerLevel;
    return $PointerLevel;
}

sub get_BaseType($$$)
{
    my $TypeDId = $_[0];
    my $TypeId = $_[1];
    my $LibVersion = $_[2];
    if(defined $Cache{'get_BaseType'}{$TypeDId}{$TypeId}{$LibVersion})
    {
        return %{$Cache{'get_BaseType'}{$TypeDId}{$TypeId}{$LibVersion}};
    }
    my %Type = %{$TypeDescr{$LibVersion}{$TypeDId}{$TypeId}};
    return %Type if(not $Type{'BaseType'}{'TDid'} and not $Type{'BaseType'}{'Tid'});
    %Type = get_BaseType($Type{'BaseType'}{'TDid'}, $Type{'BaseType'}{'Tid'}, $LibVersion);
     %{$Cache{'get_BaseType'}{$TypeDId}{$TypeId}{$LibVersion}} = %Type;
    return %Type;
}

sub get_OneStep_BaseType($$$)
{
    my $TypeDId = $_[0];
    my $TypeId = $_[1];
    my $LibVersion = $_[2];
    my %Type = %{$TypeDescr{$LibVersion}{$TypeDId}{$TypeId}};
    return %Type if(not $Type{'BaseType'}{'TDid'} and not $Type{'BaseType'}{'Tid'});
    return get_Type($Type{'BaseType'}{'TDid'}, $Type{'BaseType'}{'Tid'}, $LibVersion);
}

sub get_Type($$$)
{
    my $TypeDId = $_[0];
    my $TypeId = $_[1];
    my $LibVersion = $_[2];
    return %{$TypeDescr{$LibVersion}{$TypeDId}{$TypeId}};
}

sub mergeLibs()
{
    foreach my $FuncName (sort keys(%AddedInt))
    {#Check Added Interfaces
        next if($InternalInterfaces{$FuncName});
        next if($FuncAttr{2}{$FuncName}{'Access'} eq "private");
        next if(not $FuncAttr{2}{$FuncName}{'Header'});
        %{$CompatProblems{$FuncName}{"Added_Interface"}{"SharedLibrary"}}=(
            "Header"=>$FuncAttr{2}{$FuncName}{'Header'},
            "Line"=>$FuncAttr{2}{$FuncName}{'Line'},
            "Signature"=>get_Signature($FuncName, 2),
            "New_SoName"=>$LibInt{2}{$FuncName}  );
    }
    foreach my $FuncName (sort keys(%WithdrawnInt))
    {#Check Withdrawn Interfaces
        next if($InternalInterfaces{$FuncName});
        next if($FuncAttr{1}{$FuncName}{'Access'} eq "private");
        next if(not $FuncAttr{1}{$FuncName}{'Header'});
        %{$CompatProblems{$FuncName}{"Withdrawn_Interface"}{"SharedLibrary"}}=(
            "Header"=>$FuncAttr{1}{$FuncName}{'Header'},
            "Line"=>$FuncAttr{1}{$FuncName}{'Line'},
            "Signature"=>get_Signature($FuncName, 1),
            "Old_SoName"=>$LibInt{1}{$FuncName}  );
    }
}

sub mergeHeaders()
{
    my %SubProblems = ();
    
	prepareInterfaces(1);
	prepareInterfaces(2);
    
    initializeClassVirtFunc(1);
    initializeClassVirtFunc(2);
    
    checkVirtFuncRedefinitions(1);
    checkVirtFuncRedefinitions(2);
    
    setVirtFuncPositions(1);
    setVirtFuncPositions(2);
    
    foreach my $FuncName (sort keys(%AddedInt))
    {#Collect added interfaces attributes
        if($Functions{2}{$FuncName})
        {
            if($Functions{2}{$FuncName}{'Access'} and ($FuncAttr{2}{$FuncName}{'Access'} eq "public" or not $FuncAttr{2}{$FuncName}{'Access'}))
            {
                $FuncAttr{2}{$FuncName}{'Access'} = $Functions{2}{$FuncName}{'Access'};
            }
            if($Functions{2}{$FuncName}{'Header'})
            {
                $FuncAttr{2}{$FuncName}{'Header'} = $Functions{2}{$FuncName}{'Header'};
            }
            if($Functions{2}{$FuncName}{'Line'})
            {
                $FuncAttr{2}{$FuncName}{'Line'} = $Functions{2}{$FuncName}{'Line'};
            }
            if(not $FuncAttr{2}{$FuncName}{'Signature'})
            {
                $FuncAttr{2}{$FuncName}{'Signature'} = get_Signature($FuncName, 2);
            }
            foreach my $ParamPos (keys(%{$Functions{2}{$FuncName}{'Param'}}))
            {
                my $ParamType_Id = $Functions{2}{$FuncName}{'Param'}{$ParamPos}{'type'};
                my $ParamType_DId = getTypeDeclId_by_Ver($ParamType_Id, 2);
                my %ParamType = get_Type($ParamType_DId, $ParamType_Id, 2);
                $Dictionary_TypeName{$ParamType{'Name'}} = 1;
            }
            #Check Virtual Tables
            check_VirtualTable($FuncName, 2);
        }
    }
    foreach my $FuncName (sort keys(%WithdrawnInt))
    {#Collect withdrawn interfaces attributes
        if($Functions{1}{$FuncName})
        {
            if($Functions{1}{$FuncName}{'Access'} and ($FuncAttr{1}{$FuncName}{'Access'} eq "public" or not $FuncAttr{1}{$FuncName}{'Access'}))
            {
                $FuncAttr{1}{$FuncName}{'Access'} = $Functions{1}{$FuncName}{'Access'};
            }
            if($Functions{1}{$FuncName}{'Header'})
            {
                $FuncAttr{1}{$FuncName}{'Header'} = $Functions{1}{$FuncName}{'Header'};
            }
            if($Functions{1}{$FuncName}{'Line'})
            {
                $FuncAttr{1}{$FuncName}{'Line'} = $Functions{1}{$FuncName}{'Line'};
            }
            if(not $FuncAttr{1}{$FuncName}{'Signature'})
            {
                $FuncAttr{1}{$FuncName}{'Signature'} = get_Signature($FuncName, 1);
            }
            foreach my $ParamPos (keys(%{$Functions{1}{$FuncName}{'Param'}}))
            {
                my $ParamType_Id = $Functions{1}{$FuncName}{'Param'}{$ParamPos}{'type'};
                my $ParamType_DId = getTypeDeclId_by_Ver($ParamType_Id, 1);
                my %ParamType = get_Type($ParamType_DId, $ParamType_Id, 1);
                $Dictionary_TypeName{$ParamType{'Name'}} = 1;
            }
            #Check Virtual Tables
            check_VirtualTable($FuncName, 1);
        }
    }
    
	foreach my $FuncName (sort keys(%{$Functions{1}}))
	{#Check Interfaces
        next if($InternalInterfaces{$FuncName});
        next if($ReportedInterfaces{$FuncName});
        next if($Functions{1}{$FuncName}{'Access'} eq "private");
		next if(not $Functions{1}{$FuncName}{'MnglName'} or not $Functions{2}{$FuncName}{'MnglName'});
        next if(($Functions{1}{$FuncName}{'PureVirtual'} eq "No" and $Functions{2}{$FuncName}{'PureVirtual'} eq "Yes") or ($Functions{1}{$FuncName}{'PureVirtual'} eq "Yes" and $Functions{2}{$FuncName}{'PureVirtual'} eq "No"));
        $ReportedInterfaces{$FuncName} = 1;
        #Check Virtual Tables
        check_VirtualTable($FuncName, 1);
        #Check Attributes
		if($Functions{1}{$FuncName}{'Static'} and $Functions{2}{$FuncName}{'Static'})
		{
			if(($Functions{2}{$FuncName}{'Static'} eq "Yes") and ($Functions{1}{$FuncName}{'Static'} eq "No"))
			{
                %{$CompatProblems{$FuncName}{"Function_Become_Static"}{"Attributes"}}=(
                    "Header"=>$Functions{1}{$FuncName}{'Header'},
                    "Line"=>$Functions{1}{$FuncName}{'Line'},
                    "Signature"=>get_Signature($FuncName, 1),
                    "Old_SoName"=>$LibInt{1}{$FuncName},
                    "New_SoName"=>$LibInt{2}{$FuncName}  );
			}
			elsif(($Functions{2}{$FuncName}{'Static'} eq "No") and ($Functions{1}{$FuncName}{'Static'} eq "Yes"))
			{
                %{$CompatProblems{$FuncName}{"Function_Become_NonStatic"}{"Attributes"}}=(
                    "Header"=>$Functions{1}{$FuncName}{'Header'},
                    "Line"=>$Functions{1}{$FuncName}{'Line'},
                    "Signature"=>get_Signature($FuncName, 1),
                    "Old_SoName"=>$LibInt{1}{$FuncName},
                    "New_SoName"=>$LibInt{2}{$FuncName}  );
			}
		}
        if(($Functions{1}{$FuncName}{'Virtual'} eq "Yes") and ($Functions{2}{$FuncName}{'Virtual'} eq "Yes"))
        {
            if($Functions{1}{$FuncName}{'Position'} ne $Functions{2}{$FuncName}{'Position'})
            {
                my $Class_Id = $Functions{1}{$FuncName}{'Class'};
                my $Class_DId = getTypeDeclId_by_Ver($Class_Id, 1);
                my %Class_Type = get_Type($Class_DId, $Class_Id, 1);
                %{$CompatProblems{$FuncName}{"Virtual_Function_Position"}{unmangle($FuncName)}}=(
                "Type_Name"=>$Class_Type{'Name'},
                "Type_Type"=>$Class_Type{'Type'},
                "Header"=>$Class_Type{'Header'},
                "Line"=>$Class_Type{'Line'},
                "Old_Value"=>$Functions{1}{$FuncName}{'Position'},
                "New_Value"=>$Functions{2}{$FuncName}{'Position'},
                "Signature"=>get_Signature($FuncName, 1),
                "Target"=>unmangle($FuncName),
                "Old_SoName"=>$LibInt{1}{$FuncName},
                "New_SoName"=>$LibInt{2}{$FuncName}  );
            }
        }
		foreach my $ParamPos (sort {int($a) <=> int($b)} keys(%{$Functions{1}{$FuncName}{'Param'}}))
		{#Check Parameters
			my $ParamType1_Id = $Functions{1}{$FuncName}{'Param'}{$ParamPos}{'type'};
			my $ParamType2_Id = $Functions{2}{$FuncName}{'Param'}{$ParamPos}{'type'};
            my $ParamType1_DId = getTypeDeclId_by_Ver($ParamType1_Id, 1);
            my $ParamType2_DId = getTypeDeclId_by_Ver($ParamType2_Id, 2);
            my %ParamType1 = get_Type($ParamType1_DId, $ParamType1_Id, 1);
            my %ParamType2 = get_Type($ParamType2_DId, $ParamType2_Id, 2);
            my %ParamType1_Base = get_BaseType($ParamType1_DId, $ParamType1_Id, 1);
            my %ParamType2_Base = get_BaseType($ParamType2_DId, $ParamType2_Id, 2);
            my %ParamType1_Pure = get_PureType($ParamType1_DId, $ParamType1_Id, 1);
            my %ParamType2_Pure = get_PureType($ParamType2_DId, $ParamType2_Id, 2);
            my $ParamType1_PointerLevel = get_PointerLevel($ParamType1_DId, $ParamType1_Id, 1);
            my $ParamType2_PointerLevel = get_PointerLevel($ParamType2_DId, $ParamType2_Id, 2);
            my $Parameter_Name = $Functions{1}{$FuncName}{'Param'}{$ParamPos}{'name'};
            my ($Parameter_Target, $Parameter_Location);
            my $Parameter_Location = "";
            if($Parameter_Name)
            {
                $Parameter_Target = $Parameter_Name;
                $Parameter_Location = $Parameter_Name;
            }
            else
            {
                $Parameter_Target = $ParamPos;
                $Parameter_Location = num_to_str($ParamPos+1)." Parameter";
            }
            @RecurTypes = ();
            next if(not $ParamType1_Id or not $ParamType2_Id);
            next if(not $ParamType1{'Name'} or not $ParamType2{'Name'});
            $Dictionary_TypeName{$ParamType1{'Name'}} = 1;
            $Dictionary_TypeName{$ParamType2{'Name'}} = 1;
            if($ParamType1{'Type'} eq "Array")
            {
                if($ParamType1{'Name'} ne $ParamType2{'Name'})
                {
                    if($ParamType1{'Size'} and $ParamType2{'Size'} and ($ParamType1{'Size'} ne $ParamType2{'Size'}))
                    {
                        %{$CompatProblems{"Parameter_Type"}{$Parameter_Location}}=(
                            "Target"=>$Parameter_Target,
                            "Header"=>$Functions{1}{$FuncName}{'Header'},
                            "Line"=>$Functions{1}{$FuncName}{'Line'},
                            "Old_Value"=>$ParamType1{'Name'},
                            "New_Value"=>$ParamType2{'Name'},
                            "Old_SoName"=>$LibInt{1}{$FuncName},
                            "New_SoName"=>$LibInt{2}{$FuncName},
                            "Old_Size"=>$ParamType1{'Size'}*$ParamType1_Base{'Size'},
                            "New_Size"=>$ParamType2{'Size'}*$ParamType2_Base{'Size'},
                            "InitialType_Type"=>"Array"  );
                    }
                }
            }
            if($ParamType1_Base{'Name'} and $ParamType2_Base{'Name'} and ($ParamType1_Base{'Name'} ne $ParamType2_Base{'Name'}) and ($ParamType1{'Name'} ne $ParamType2{'Name'}))
            {#Param type changed
                if($ParamType1_Base{'Size'} and $ParamType2_Base{'Size'} and ($ParamType1_Base{'Size'} ne $ParamType2_Base{'Size'}))
                {
                    if($ParamType1_Base{'Name'} eq $ParamType1{'Name'})
                    {
                        if($ParamType1_Pure{'Size'} ne $ParamType2_Pure{'Size'})
                        {
                            %{$CompatProblems{$FuncName}{"Parameter_Type_And_Size"}{$Parameter_Location}}=(
                                "Header"=>$Functions{1}{$FuncName}{'Header'},
                                "Line"=>$Functions{1}{$FuncName}{'Line'},
                                "Old_Value"=>$ParamType1{'Name'},
                                "New_Value"=>$ParamType2{'Name'},
                                "Signature"=>get_Signature($FuncName, 1),
                                "Old_SoName"=>$LibInt{1}{$FuncName},
                                "New_SoName"=>$LibInt{2}{$FuncName},
                                "Target"=>$Parameter_Target,
                                "Old_Size"=>$ParamType1{'Size'},
                                "New_Size"=>$ParamType2{'Size'},
                                "InitialType_Type"=>$ParamType1_Pure{'Type'}  );
                        }
                        else
                        {
                            %{$CompatProblems{$FuncName}{"Parameter_Type"}{$Parameter_Location}}=(
                                "Header"=>$Functions{1}{$FuncName}{'Header'},
                                "Line"=>$Functions{1}{$FuncName}{'Line'},
                                "Old_Value"=>$ParamType1{'Name'},
                                "New_Value"=>$ParamType2{'Name'},
                                "Signature"=>get_Signature($FuncName, 1),
                                "Old_SoName"=>$LibInt{1}{$FuncName},
                                "New_SoName"=>$LibInt{2}{$FuncName},
                                "Target"=>$Parameter_Target,
                                "InitialType_Type"=>$ParamType1_Pure{'Type'}  );
                        }
                    }
                    else
                    {
                        %{$CompatProblems{$FuncName}{"Parameter_BaseType"}{$Parameter_Location}}=(
                            "Header"=>$Functions{1}{$FuncName}{'Header'},
                            "Line"=>$Functions{1}{$FuncName}{'Line'},
                            "Old_Value"=>$ParamType1_Base{'Name'},
                            "New_Value"=>$ParamType2_Base{'Name'},
                            "Signature"=>get_Signature($FuncName, 1),
                            "Old_SoName"=>$LibInt{1}{$FuncName},
                            "New_SoName"=>$LibInt{2}{$FuncName},
                            "Target"=>$Parameter_Target,
                            "Old_Size"=>$ParamType1_Base{'Size'},
                            "New_Size"=>$ParamType2_Base{'Size'},
                            "InitialType_Type"=>$ParamType1_Pure{'Type'}  );
                    }
                }
                elsif($ParamType1_Base{'Size'} and $ParamType2_Base{'Size'} and $ParamType1_Pure{'Size'} eq $ParamType2_Pure{'Size'})
                {
                    %{$CompatProblems{$FuncName}{"Parameter_Type"}{$Parameter_Location}}=(
                        "Header"=>$Functions{1}{$FuncName}{'Header'},
                        "Line"=>$Functions{1}{$FuncName}{'Line'},
                        "Old_Value"=>$ParamType1{'Name'},
                        "New_Value"=>$ParamType2{'Name'},
                        "Signature"=>get_Signature($FuncName, 1),
                        "Old_SoName"=>$LibInt{1}{$FuncName},
                        "New_SoName"=>$LibInt{2}{$FuncName},
                        "Target"=>$Parameter_Target,
                        "InitialType_Type"=>$ParamType1_Pure{'Type'}  );
                }
            }
            if(($ParamType1_PointerLevel ne "") and ($ParamType2_PointerLevel ne "") and ($ParamType1_PointerLevel ne $ParamType2_PointerLevel))
            {
                if($ParamType1_Pure{'Size'} ne $ParamType2_Pure{'Size'})
                {
                    %{$CompatProblems{$FuncName}{"Parameter_PointerLevel_And_Size"}{$Parameter_Location}}=(
                        "Header"=>$Functions{1}{$FuncName}{'Header'},
                        "Line"=>$Functions{1}{$FuncName}{'Line'},
                        "Old_Value"=>$ParamType1_PointerLevel,
                        "New_Value"=>$ParamType2_PointerLevel,
                        "Signature"=>get_Signature($FuncName, 1),
                        "Old_SoName"=>$LibInt{1}{$FuncName},
                        "New_SoName"=>$LibInt{2}{$FuncName},
                        "Target"=>$Parameter_Target,
                        "Old_Size"=>$ParamType1_Pure{'Size'},
                        "New_Size"=>$ParamType2_Pure{'Size'}  );
                }
                else
                {
                    %{$CompatProblems{$FuncName}{"Parameter_PointerLevel"}{$Parameter_Location}}=(
                        "Header"=>$Functions{1}{$FuncName}{'Header'},
                        "Line"=>$Functions{1}{$FuncName}{'Line'},
                        "Old_Value"=>$ParamType1_PointerLevel,
                        "New_Value"=>$ParamType2_PointerLevel,
                        "Signature"=>get_Signature($FuncName, 1),
                        "Old_SoName"=>$LibInt{1}{$FuncName},
                        "New_SoName"=>$LibInt{2}{$FuncName},
                        "Target"=>$Parameter_Target  );
                }
            }
            %SubProblems = mergeTypes($ParamType1_Id, $ParamType1_DId, $ParamType2_Id, $ParamType2_DId);
            foreach my $SubProblemType (keys(%SubProblems))
            {
                foreach my $SubLocation (keys(%{$SubProblems{$SubProblemType}}))
                {
                    my $NewLocation = $Parameter_Location;
                    if($SubLocation and $NewLocation)
                    {
                        $NewLocation .= "->".$SubLocation;
                    }
                    %{$CompatProblems{$FuncName}{$SubProblemType}{$NewLocation}} = %{$SubProblems{$SubProblemType}{$SubLocation}};
                    $CompatProblems{$FuncName}{$SubProblemType}{$NewLocation}{'Old_SoName'} = $LibInt{1}{$FuncName};
                    $CompatProblems{$FuncName}{$SubProblemType}{$NewLocation}{'New_SoName'} = $LibInt{2}{$FuncName};
                    $CompatProblems{$FuncName}{$SubProblemType}{$NewLocation}{'Signature'} = get_Signature($FuncName, 1);
                    $CompatProblems{$FuncName}{$SubProblemType}{$NewLocation}{'Parameter_Position'} = $ParamPos;
                    $CompatProblems{$FuncName}{$SubProblemType}{$NewLocation}{'Parameter_Name'} = $Parameter_Name;
                    $CompatProblems{$FuncName}{$SubProblemType}{$NewLocation}{'Parameter_Type_Name'} = $ParamType1{'Name'};
                    if($SubLocation !~ /\-\>/)
                    {
                        $CompatProblems{$FuncName}{$SubProblemType}{$NewLocation}{'Start_Type_Name'} = $ParamType1{'Name'};
                    }
                }
            }
		}
		#Check Return Type
		my $ReturnType1_Id = $Functions{1}{$FuncName}{'Return'};
		my $ReturnType2_Id = $Functions{2}{$FuncName}{'Return'};
        my $ReturnType1_DId = getTypeDeclId_by_Ver($ReturnType1_Id, 1);
        my $ReturnType2_DId = getTypeDeclId_by_Ver($ReturnType2_Id, 2);
        my %ReturnType1 = get_Type($ReturnType1_DId, $ReturnType1_Id, 1);
        my %ReturnType2 = get_Type($ReturnType2_DId, $ReturnType2_Id, 2);
        my %ReturnType1_Base = get_BaseType($ReturnType1_DId, $ReturnType1_Id, 1);
        my %ReturnType2_Base = get_BaseType($ReturnType2_DId, $ReturnType2_Id, 2);
        my %ReturnType1_Pure = get_PureType($ReturnType1_DId, $ReturnType1_Id, 1);
        my %ReturnType2_Pure = get_PureType($ReturnType2_DId, $ReturnType2_Id, 2);
        my $ReturnType1_PointerLevel = get_PointerLevel($ReturnType1_DId, $ReturnType1_Id, 1);
        my $ReturnType2_PointerLevel = get_PointerLevel($ReturnType2_DId, $ReturnType2_Id, 2);
        @RecurTypes = ();
        if($ReturnType1{'Type'} eq "Array")
        {
            if($ReturnType1{'Name'} ne $ReturnType2{'Name'})
            {
                if($ReturnType1{'Size'} and $ReturnType2{'Size'} and ($ReturnType1{'Size'} ne $ReturnType2{'Size'}))
                {
                    %{$CompatProblems{"Return_Type_And_Size"}{"RetVal"}}=(
                        "Header"=>$Functions{1}{$FuncName}{'Header'},
                        "Line"=>$Functions{1}{$FuncName}{'Line'},
                        "Old_Value"=>$ReturnType1{'Name'},
                        "New_Value"=>$ReturnType2{'Name'},
                        "Signature"=>get_Signature($FuncName, 1),
                        "Old_SoName"=>$LibInt{1}{$FuncName},
                        "New_SoName"=>$LibInt{2}{$FuncName},
                        "Old_Size"=>$ReturnType1{'Size'}*$ReturnType1_Base{'Size'},
                        "New_Size"=>$ReturnType2{'Size'}*$ReturnType2_Base{'Size'},
                        "InitialType_Type"=>"Array"  );
                }
            }
        }
        if($ReturnType1_Base{'Name'} and $ReturnType2_Base{'Name'} and ($ReturnType1_Base{'Name'} ne $ReturnType2_Base{'Name'}) and ($ReturnType1{'Name'} ne $ReturnType2{'Name'}))
        {#return type changed
            if($ReturnType1_Base{'Size'} and $ReturnType2_Base{'Size'} and ($ReturnType1_Base{'Size'} ne $ReturnType2_Base{'Size'}))
            {
                if($ReturnType1_Base{'Name'} eq $ReturnType1{'Name'})
                {
                    if($ReturnType1_Pure{'Size'} ne $ReturnType2_Pure{'Size'})
                    {
                        %{$CompatProblems{$FuncName}{"Return_Type_And_Size"}{"RetVal"}}=(
                            "Header"=>$Functions{1}{$FuncName}{'Header'},
                            "Line"=>$Functions{1}{$FuncName}{'Line'},
                            "Old_Value"=>$ReturnType1{'Name'},
                            "New_Value"=>$ReturnType2{'Name'},
                            "Signature"=>get_Signature($FuncName, 1),
                            "Old_SoName"=>$LibInt{1}{$FuncName},
                            "New_SoName"=>$LibInt{2}{$FuncName},
                            "Old_Size"=>$ReturnType1_Pure{'Size'},
                            "New_Size"=>$ReturnType2_Pure{'Size'},
                            "InitialType_Type"=>$ReturnType1_Pure{'Type'}  );
                    }
                    else
                    {
                        %{$CompatProblems{$FuncName}{"Return_Type"}{"RetVal"}}=(
                            "Header"=>$Functions{1}{$FuncName}{'Header'},
                            "Line"=>$Functions{1}{$FuncName}{'Line'},
                            "Old_Value"=>$ReturnType1{'Name'},
                            "New_Value"=>$ReturnType2{'Name'},
                            "Signature"=>get_Signature($FuncName, 1),
                            "Old_SoName"=>$LibInt{1}{$FuncName},
                            "New_SoName"=>$LibInt{2}{$FuncName},
                            "InitialType_Type"=>$ReturnType1_Pure{'Type'}  );
                    }
                }
                else
                {
                    %{$CompatProblems{$FuncName}{"Return_BaseType"}{"RetVal"}}=(
                        "Header"=>$Functions{1}{$FuncName}{'Header'},
                        "Line"=>$Functions{1}{$FuncName}{'Line'},
                        "Old_Value"=>$ReturnType1_Base{'Name'},
                        "New_Value"=>$ReturnType2_Base{'Name'},
                        "Signature"=>get_Signature($FuncName, 1),
                        "Old_SoName"=>$LibInt{1}{$FuncName},
                        "New_SoName"=>$LibInt{2}{$FuncName},
                        "Old_Size"=>$ReturnType1_Base{'Size'},
                        "New_Size"=>$ReturnType2_Base{'Size'},
                        "InitialType_Type"=>$ReturnType1_Pure{'Type'}  );
                }
            }
            elsif($ReturnType1_Base{'Size'} and $ReturnType2_Base{'Size'} and $ReturnType1_Pure{'Size'} eq $ReturnType2_Pure{'Size'})
            {
                %{$CompatProblems{$FuncName}{"Return_Type"}{"RetVal"}}=(
                    "Header"=>$Functions{1}{$FuncName}{'Header'},
                    "Line"=>$Functions{1}{$FuncName}{'Line'},
                    "Old_Value"=>$ReturnType1{'Name'},
                    "New_Value"=>$ReturnType2{'Name'},
                    "Signature"=>get_Signature($FuncName, 1),
                    "Old_SoName"=>$LibInt{1}{$FuncName},
                    "New_SoName"=>$LibInt{2}{$FuncName},
                    "InitialType_Type"=>$ReturnType1_Pure{'Type'}  );
            }
        }
        if(($ReturnType1_PointerLevel ne "") and ($ReturnType2_PointerLevel ne "") and ($ReturnType1_PointerLevel ne $ReturnType2_PointerLevel))
        {
            if($ReturnType1_Pure{'Size'} ne $ReturnType2_Pure{'Size'})
            {
                %{$CompatProblems{$FuncName}{"Return_PointerLevel_And_Size"}{"RetVal"}}=(
                    "Header"=>$Functions{1}{$FuncName}{'Header'},
                    "Line"=>$Functions{1}{$FuncName}{'Line'},
                    "Old_Value"=>$ReturnType1_PointerLevel,
                    "New_Value"=>$ReturnType2_PointerLevel,
                    "Signature"=>get_Signature($FuncName, 1),
                    "Old_SoName"=>$LibInt{1}{$FuncName},
                    "New_SoName"=>$LibInt{2}{$FuncName},
                    "Old_Size"=>$ReturnType1_Pure{'Size'},
                    "New_Size"=>$ReturnType2_Pure{'Size'}  );
            }
            else
            {
                %{$CompatProblems{$FuncName}{"Return_PointerLevel"}{"RetVal"}}=(
                    "Header"=>$Functions{1}{$FuncName}{'Header'},
                    "Line"=>$Functions{1}{$FuncName}{'Line'},
                    "Old_Value"=>$ReturnType1_PointerLevel,
                    "New_Value"=>$ReturnType2_PointerLevel,
                    "Signature"=>get_Signature($FuncName, 1),
                    "Old_SoName"=>$LibInt{1}{$FuncName},
                    "New_SoName"=>$LibInt{2}{$FuncName}  );
            }
        }
        if($ReturnType1_Id and $ReturnType2_Id)
        {
            %SubProblems = mergeTypes($ReturnType1_Id, $ReturnType1_DId, $ReturnType2_Id, $ReturnType2_DId);
            foreach my $SubProblemType (keys(%SubProblems))
            {
                foreach my $SubLocation (keys(%{$SubProblems{$SubProblemType}}))
                {
                    my $NewLocation = "RetVal";
                    if($SubLocation)
                    {
                        $NewLocation .= "->".$SubLocation;
                    }
                    %{$CompatProblems{$FuncName}{$SubProblemType}{$NewLocation}} = %{$SubProblems{$SubProblemType}{$SubLocation}};
                    $CompatProblems{$FuncName}{$SubProblemType}{$NewLocation}{'Old_SoName'} = $LibInt{1}{$FuncName};
                    $CompatProblems{$FuncName}{$SubProblemType}{$NewLocation}{'New_SoName'} = $LibInt{2}{$FuncName};
                    $CompatProblems{$FuncName}{$SubProblemType}{$NewLocation}{'Signature'} = get_Signature($FuncName, 1);
                    $CompatProblems{$FuncName}{$SubProblemType}{$NewLocation}{'Return_Type_Name'} = $ReturnType1{'Name'};
                    if($SubLocation !~ /\-\>/)
                    {
                        $CompatProblems{$FuncName}{$SubProblemType}{$NewLocation}{'Start_Type_Name'} = $ReturnType1{'Name'};
                    }
                }
            }
        }
        
		#Check Object Type
		my $ObjectType1_Id = $Functions{1}{$FuncName}{'Class'};
		my $ObjectType2_Id = $Functions{2}{$FuncName}{'Class'};
        my $ObjectType1_DId = getTypeDeclId_by_Ver($ObjectType1_Id, 1);
        my $ObjectType2_DId = getTypeDeclId_by_Ver($ObjectType2_Id, 2);
        my %ObjectType1 = get_Type($ObjectType1_DId, $ObjectType1_Id, 1);
        my %ObjectType2 = get_Type($ObjectType2_DId, $ObjectType2_Id, 2);
        @RecurTypes = ();
        if($ObjectType1_Id and $ObjectType2_Id)
        {
		    %SubProblems = mergeTypes($ObjectType1_Id, $ObjectType1_DId, $ObjectType2_Id, $ObjectType2_DId);
            foreach my $SubProblemType (keys(%SubProblems))
            {
                foreach my $SubLocation (keys(%{$SubProblems{$SubProblemType}}))
                {
                    my $NewLocation = "Obj";
                    if($SubLocation)
                    {
                        $NewLocation .= "->".$SubLocation;
                    }
                    %{$CompatProblems{$FuncName}{$SubProblemType}{$NewLocation}} = %{$SubProblems{$SubProblemType}{$SubLocation}};
                    $CompatProblems{$FuncName}{$SubProblemType}{$NewLocation}{'Old_SoName'} = $LibInt{1}{$FuncName};
                    $CompatProblems{$FuncName}{$SubProblemType}{$NewLocation}{'New_SoName'} = $LibInt{2}{$FuncName};
                    $CompatProblems{$FuncName}{$SubProblemType}{$NewLocation}{'Signature'} = get_Signature($FuncName, 1);
                    $CompatProblems{$FuncName}{$SubProblemType}{$NewLocation}{'Object_Type_Name'} = $ObjectType1{'Name'};
                    if($SubLocation !~ /\-\>/)
                    {
                        $CompatProblems{$FuncName}{$SubProblemType}{$NewLocation}{'Start_Type_Name'} = $ObjectType1{'Name'};
                    }
                }
            }
        }
	}
    #Priority
    set_Problems_Priority();
}

my $ContentSpanStart = "<span class=\"section\" onclick=\"javascript:showContent(this, 'CONTENT_ID')\">\n";
my $ContentSpanEnd = "</span>\n";
my $ContentDivStart = "<div id=\"CONTENT_ID\" style=\"display:none;\">\n";
my $ContentDivEnd = "</div>\n";

sub htmlSpecChars($)
{
    my $Str = $_[0];
    $Str =~ s/</&lt;/g;
    $Str =~ s/>/&gt;/g;
    return $Str;
}

sub highLight_Signature($)
{
    my $Signature = $_[0];
    return highLight_Signature_PPos_Italic($Signature, "", 0);
}

sub highLight_Signature_Italic($)
{
    my $Signature = $_[0];
    return highLight_Signature_PPos_Italic($Signature, "", 1);
}

sub highLight_Signature_PPos_Italic($$$)
{
    my $Signature = $_[0];
    my $Parameter_Position = $_[1];
    my $ItalicParams = $_[2];
    my @Parts = get_Signature_Parts($Signature);
    my $Part_Num = 0;
    foreach my $Part (@Parts)
    {
        
        $Part =~ s/[ ]*\Z//g;
        $Part =~ s/\A[ ]*//g;
        my $Part_Styled = $Part;
        if($ItalicParams and not $Dictionary_TypeName{$Part})
        {
            if(($Parameter_Position ne "") and ($Part_Num == $Parameter_Position))
            {
                $Part_Styled =~ s!([a-z0-9_]+)\Z!<span style='font-style:italic;color:Red;'>$1</span>!ig;
            }
            else
            {
                $Part_Styled =~ s!([a-z0-9_]+)\Z!<span style='font-style:italic;'>$1</span>!ig;
            }
        }
        $Part_Styled = "<span style='white-space:nowrap;'>".$Part_Styled."</span>";
        substr($Signature, index($Signature, $Part), length($Part), $Part_Styled);
        $Part_Num += 1;
    }
    $Signature =~ s!\A([^()]*)(\(.*\))([^()]*)\Z!$1<span class\=\'interface_signature\'\>$2\</span>$3!o;
    $Signature =~ s!\[\]![<span style='padding-left:2px;'>]</span>!g;
    $Signature =~ s!operator=!operator<span style='padding-left:2px'>=</span>!g;
    return $Signature;
}

sub get_Signature_Parts($)
{
    my $Signature = $_[0];
    my @Parts = ();
    my $Bracket_Num = 0;
    my $Parameters = $Signature;
    my $Part_Num = 0;
    $Parameters =~ s/.+?\((.*)\)\Z/$1/oi;
    foreach my $Pos (0 .. length($Parameters) - 1)
    {
        my $Symbol = substr($Parameters, $Pos, 1);
        $Bracket_Num += 1 if($Symbol eq "(");
        $Bracket_Num -= 1 if($Symbol eq ")");
        if($Symbol eq "," and $Bracket_Num==0)
        {
            $Part_Num += 1;
        }
        else
        {
            $Parts[$Part_Num] .= $Symbol;
        }
    }
    return @Parts;
}

my %TypeProblems_Kind=(
    "Added_Virtual_Function"=>1,
    "Withdrawn_Virtual_Function"=>1,
    "Virtual_Function_Position"=>1,
    "Virtual_Function_Redefinition"=>1,
    "Virtual_Function_Redefinition_B"=>1,
    "Size"=>1,
    "Added_Member"=>1,
    "Added_Middle_Member"=>1,
    "Withdrawn_Member_And_Size"=>1,
    "Withdrawn_Member"=>1,
    "Withdrawn_Middle_Member_And_Size"=>1,
    "Member_Rename"=>1,
    "Enum_Member_Value"=>1,
    "Enum_Member_Name"=>1,
    "Member_Type_And_Size"=>1,
    "Member_Type"=>1,
    "Member_BaseType"=>1,
    "Member_PointerLevel_And_Size"=>1,
    "Member_PointerLevel"=>1
);

my %InterfaceProblems_Kind=(
    "Added_Interface"=>1,
    "Withdrawn_Interface"=>1,
    "Function_Become_Static"=>1,
    "Function_Become_NonStatic"=>1,
    "Parameter_Type_And_Size"=>1,
    "Parameter_Type"=>1,
    "Parameter_BaseType"=>1,
    "Parameter_PointerLevel_And_Size"=>1,
    "Parameter_PointerLevel"=>1,
    "Return_Type_And_Size"=>1,
    "Return_Type"=>1,
    "Return_BaseType"=>1,
    "Return_PointerLevel_And_Size"=>1,
    "Return_PointerLevel"=>1
);

sub testSystem_cpp()
{
    print "testing on C++ library changes\n";
    my @DataDefs_v1 = ();
    my @Sources_v1 = ();
    my @DataDefs_v2 = ();
    my @Sources_v2 = ();
    
    #Added_Virtual_Function
    @DataDefs_v1 = (@DataDefs_v1, "class type_test_added_virtual_function\n{\npublic:\n    int func1(int param);\n    virtual int func2(int param);\n};");
    @Sources_v1 = (@Sources_v1, "int type_test_added_virtual_function::func1(int param)\n{\n    return param;\n}");
    @Sources_v1 = (@Sources_v1, "int type_test_added_virtual_function::func2(int param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "class type_test_added_virtual_function\n{\npublic:\n    virtual int func1(int param);\n    virtual int func2(int param);\n};");
    @Sources_v2 = (@Sources_v2, "int type_test_added_virtual_function::func1(int param)\n{\n    return param;\n}");
    @Sources_v2 = (@Sources_v2, "int type_test_added_virtual_function::func2(int param)\n{\n    return param;\n}");
    
    #Withdrawn_Virtual_Function
    @DataDefs_v1 = (@DataDefs_v1, "class type_test_withdrawn_virtual_function\n{\npublic:\n    virtual int func1(int param);\n    virtual int func2(int param);\n};");
    @Sources_v1 = (@Sources_v1, "int type_test_withdrawn_virtual_function::func1(int param)\n{\n    return param;\n}");
    @Sources_v1 = (@Sources_v1, "int type_test_withdrawn_virtual_function::func2(int param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "class type_test_withdrawn_virtual_function\n{\npublic:\n    int func1(int param);\n    virtual int func2(int param);\n};");
    @Sources_v2 = (@Sources_v2, "int type_test_withdrawn_virtual_function::func1(int param)\n{\n    return param;\n}");
    @Sources_v2 = (@Sources_v2, "int type_test_withdrawn_virtual_function::func2(int param)\n{\n    return param;\n}");
    
    #Virtual_Function_Position
    @DataDefs_v1 = (@DataDefs_v1, "class type_test_virtual_function_position\n{\npublic:\n    virtual int func1(int param);\n    virtual int func2(int param);\n};");
    @Sources_v1 = (@Sources_v1, "int type_test_virtual_function_position::func1(int param)\n{\n    return param;\n}");
    @Sources_v1 = (@Sources_v1, "int type_test_virtual_function_position::func2(int param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "class type_test_virtual_function_position\n{\npublic:\n    virtual int func2(int param);\n    virtual int func1(int param);\n};");
    @Sources_v2 = (@Sources_v2, "int type_test_virtual_function_position::func1(int param)\n{\n    return param;\n}");
    @Sources_v2 = (@Sources_v2, "int type_test_virtual_function_position::func2(int param)\n{\n    return param;\n}");
    
    
    @DataDefs_v1 = (@DataDefs_v1, "class type_test_virtual_function_position_safe_replace\n{\npublic:\n    virtual int func1(int param);\n    virtual int func2(int param);\n};");
    @Sources_v1 = (@Sources_v1, "int type_test_virtual_function_position_safe_replace::func1(int param)\n{\n    return param;\n}");
    @Sources_v1 = (@Sources_v1, "int type_test_virtual_function_position_safe_replace::func2(int param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "class type_test_virtual_function_position_safe_replace\n{\npublic:\n    virtual int func2(int param);\n    virtual int func1(int param);\n};");
    @Sources_v2 = (@Sources_v2, "int type_test_virtual_function_position_safe_replace::func1(int param)\n{\n    return param;\n}");
    @Sources_v2 = (@Sources_v2, "int type_test_virtual_function_position_safe_replace::func2(int param)\n{\n    return param;\n}");
    
    #Virtual table changes
    @DataDefs_v1 = (@DataDefs_v1, "class type_test_virtual_table_base\n{\npublic:\n    virtual int func1(int param);\n    virtual int func2(int param);\n};");
    @DataDefs_v1 = (@DataDefs_v1, "class type_test_virtual_table:public type_test_virtual_table_base\n{\npublic:\n    virtual int func1(int param);\n    virtual int func2(int param);\n};");
    @Sources_v1 = (@Sources_v1, "int type_test_virtual_table_base::func1(int param)\n{\n    return param;\n}");
    @Sources_v1 = (@Sources_v1, "int type_test_virtual_table_base::func2(int param)\n{\n    return param;\n}");
    @Sources_v1 = (@Sources_v1, "int type_test_virtual_table::func1(int param)\n{\n    return param;\n}");
    @Sources_v1 = (@Sources_v1, "int type_test_virtual_table::func2(int param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "class type_test_virtual_table_base\n{\npublic:\n    virtual int func1(int param);\n    virtual int func2(int param);\n};");
    @DataDefs_v2 = (@DataDefs_v2, "class type_test_virtual_table:public type_test_virtual_table_base\n{\npublic:\n    virtual int func2(int param);\n    virtual int func1(int param);\n};");
    @Sources_v2 = (@Sources_v2, "int type_test_virtual_table_base::func1(int param)\n{\n    return param;\n}");
    @Sources_v2 = (@Sources_v2, "int type_test_virtual_table_base::func2(int param)\n{\n    return param;\n}");
    @Sources_v2 = (@Sources_v2, "int type_test_virtual_table::func1(int param)\n{\n    return param;\n}");
    @Sources_v2 = (@Sources_v2, "int type_test_virtual_table::func2(int param)\n{\n    return param;\n}");
    
    #Virtual_Function_Redefinition
    @DataDefs_v1 = (@DataDefs_v1, "class type_test_virtual_function_redefinition_base\n{\npublic:\n    virtual int func1(int param);\n    virtual int func2(int param);\n};");
    @DataDefs_v1 = (@DataDefs_v1, "class type_test_virtual_function_redefinition:public type_test_virtual_function_redefinition_base\n{\npublic:\n    virtual int func3(int param);\n};");
    @Sources_v1 = (@Sources_v1, "int type_test_virtual_function_redefinition_base::func1(int param)\n{\n    return param;\n}");
    @Sources_v1 = (@Sources_v1, "int type_test_virtual_function_redefinition_base::func2(int param)\n{\n    return param;\n}");
    @Sources_v1 = (@Sources_v1, "int type_test_virtual_function_redefinition::func3(int param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "class type_test_virtual_function_redefinition_base\n{\npublic:\n    virtual int func1(int param);\n    virtual int func2(int param);\n};");
    @DataDefs_v2 = (@DataDefs_v2, "class type_test_virtual_function_redefinition:public type_test_virtual_function_redefinition_base\n{\npublic:\n    virtual int func2(int param);\n    virtual int func3(int param);\n};");
    @Sources_v2 = (@Sources_v2, "int type_test_virtual_function_redefinition_base::func1(int param){\n    return param;\n}");
    @Sources_v2 = (@Sources_v2, "int type_test_virtual_function_redefinition_base::func2(int param){\n    return param;\n}");
    @Sources_v2 = (@Sources_v2, "int type_test_virtual_function_redefinition::func2(int param)\n{\n    return param;\n}");
    @Sources_v2 = (@Sources_v2, "int type_test_virtual_function_redefinition::func3(int param)\n{\n    return param;\n}");
    
    #Size
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_size\n{\npublic:\n    virtual type_test_size func1(type_test_size param);\n    int i;\n    long j;\n    double k;\n    type_test_size* p;\n};");
    @Sources_v1 = (@Sources_v1, "type_test_size type_test_size::func1(type_test_size param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_size\n{\npublic:\n    virtual type_test_size func1(type_test_size param);\n    int i;\n    long j;\n    double k;\n    type_test_size* p;\n    int added_member;\n};");
    @Sources_v2 = (@Sources_v2, "type_test_size type_test_size::func1(type_test_size param)\n{\n    return param;\n}");
    
    #Added_Member
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_added_member\n{\npublic:\n    virtual type_test_added_member func1(type_test_added_member param);\n    int i;\n    long j;\n    double k;\n    type_test_added_member* p;\n};");
    @Sources_v1 = (@Sources_v1, "type_test_added_member type_test_added_member::func1(type_test_added_member param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_added_member\n{\npublic:\n    virtual type_test_added_member func1(type_test_added_member param);\n    int i;\n    long j;\n    double k;\n    type_test_added_member* p;\n    int added_member;\n};");
    @Sources_v2 = (@Sources_v2, "type_test_added_member type_test_added_member::func1(type_test_added_member param)\n{\n    return param;\n}");
    
    #Added Bitfield
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_added_bitfield\n{\npublic:\n    virtual type_test_added_bitfield func1(type_test_added_bitfield param);\n    int i;\n    long j;\n    double k;\n    int b1 : 32;\n    int b2 : 31;\n    type_test_added_bitfield* p;\n};");
    @Sources_v1 = (@Sources_v1, "type_test_added_bitfield type_test_added_bitfield::func1(type_test_added_bitfield param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_added_bitfield\n{\npublic:\n    virtual type_test_added_bitfield func1(type_test_added_bitfield param);\n    int i;\n    long j;\n    double k;\n    int b1 : 32;\n    int b2 : 31;\n    int added_bitfield : 1;\n    type_test_added_bitfield* p;\n};");
    @Sources_v2 = (@Sources_v2, "type_test_added_bitfield type_test_added_bitfield::func1(type_test_added_bitfield param)\n{\n    return param;\n}");
    
    #Withdrawn Bitfield
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_withdrawn_bitfield\n{\npublic:\n    virtual type_test_withdrawn_bitfield func1(type_test_withdrawn_bitfield param);\n    int i;\n    long j;\n    double k;\n    int b1 : 32;\n    int b2 : 31;\n    int withdrawn_bitfield : 1;\n    type_test_withdrawn_bitfield* p;\n};");
    @Sources_v1 = (@Sources_v1, "type_test_withdrawn_bitfield type_test_withdrawn_bitfield::func1(type_test_withdrawn_bitfield param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_withdrawn_bitfield\n{\npublic:\n    virtual type_test_withdrawn_bitfield func1(type_test_withdrawn_bitfield param);\n    int i;\n    long j;\n    double k;\n    int b1 : 32;\n    int b2 : 31;\n    type_test_withdrawn_bitfield* p;\n};");
    @Sources_v2 = (@Sources_v2, "type_test_withdrawn_bitfield type_test_withdrawn_bitfield::func1(type_test_withdrawn_bitfield param)\n{\n    return param;\n}");
    
    #Added_Middle_Member
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_added_middle_member\n{\npublic:\n    virtual type_test_added_middle_member func1(type_test_added_middle_member param);\n    int i;\n    long j;\n    double k;\n    type_test_added_middle_member* p;\n};");
    @Sources_v1 = (@Sources_v1, "type_test_added_middle_member type_test_added_middle_member::func1(type_test_added_middle_member param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_added_middle_member\n{\npublic:\n    virtual type_test_added_middle_member func1(type_test_added_middle_member param);\n    int i;\n    int added_middle_member;\n    long j;\n    double k;\n    type_test_added_middle_member* p;\n};");
    @Sources_v2 = (@Sources_v2, "type_test_added_middle_member type_test_added_middle_member::func1(type_test_added_middle_member param)\n{\n    return param;\n}");
    
    #Member_Rename
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_member_rename\n{\npublic:\n    virtual type_test_member_rename func1(type_test_member_rename param);\n    long i;\n    long j;\n    double k;\n    type_test_member_rename* p;\n};");
    @Sources_v1 = (@Sources_v1, "type_test_member_rename type_test_member_rename::func1(type_test_member_rename param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_member_rename\n{\npublic:\n    virtual type_test_member_rename func1(type_test_member_rename param);\n    long long* renamed_member;\n    long j;\n    double k;\n    type_test_member_rename* p;\n};");
    @Sources_v2 = (@Sources_v2, "type_test_member_rename type_test_member_rename::func1(type_test_member_rename param)\n{\n    return param;\n}");
    
    #Withdrawn_Member_And_Size
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_withdrawn_member\n{\npublic:\n    virtual type_test_withdrawn_member func1(type_test_withdrawn_member param);\n    int i;\n    long j;\n    double k;\n    type_test_withdrawn_member* p;\n    int withdrawn_member;\n};");
    @Sources_v1 = (@Sources_v1, "type_test_withdrawn_member type_test_withdrawn_member::func1(type_test_withdrawn_member param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_withdrawn_member\n{\npublic:\n    virtual type_test_withdrawn_member func1(type_test_withdrawn_member param);\n    int i;\n    long j;\n    double k;\n    type_test_withdrawn_member* p;\n};");
    @Sources_v2 = (@Sources_v2, "type_test_withdrawn_member type_test_withdrawn_member::func1(type_test_withdrawn_member param)\n{\n    return param;\n}");
    
    #Withdrawn_Middle_Member_And_Size
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_withdrawn_middle_member\n{\npublic:\n    virtual type_test_withdrawn_middle_member func1(type_test_withdrawn_middle_member param);\n    int i;\n    int withdrawn_middle_member;\n    long j;\n    double k;\n    type_test_withdrawn_middle_member* p;\n};");
    @Sources_v1 = (@Sources_v1, "type_test_withdrawn_middle_member type_test_withdrawn_middle_member::func1(type_test_withdrawn_middle_member param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_withdrawn_middle_member\n{\npublic:\n    virtual type_test_withdrawn_middle_member func1(type_test_withdrawn_middle_member param);\n    int i;\n    long j;\n    double k;\n    type_test_withdrawn_middle_member* p;\n};");
    @Sources_v2 = (@Sources_v2, "type_test_withdrawn_middle_member type_test_withdrawn_middle_member::func1(type_test_withdrawn_middle_member param)\n{\n    return param;\n}");
    
    #Enum_Member_Value
    @DataDefs_v1 = (@DataDefs_v1, "enum type_test_enum_member_value_change\n{\n    MEMBER_1=1,\n    MEMBER_2=2\n};");
    @DataDefs_v1 = (@DataDefs_v1, "int func_test_enum_member_value_change(enum type_test_enum_member_value_change param);");
    @Sources_v1 = (@Sources_v1,
"int func_test_enum_member_value_change(enum type_test_enum_member_value_change param)
{
    switch(param)
    {
        case 1:
            return 1;
        case 2:
            return 2;
    }
    return 0;
}");
    
    @DataDefs_v2 = (@DataDefs_v2, "enum type_test_enum_member_value_change\n{\n    MEMBER_1=2,\n    MEMBER_2=1\n};");
    @DataDefs_v2 = (@DataDefs_v2, "int func_test_enum_member_value_change(enum type_test_enum_member_value_change param);");
    @Sources_v2 = (@Sources_v2,
"int func_test_enum_member_value_change(enum type_test_enum_member_value_change param)
{
    switch(param)
    {
        case 1:
            return 1;
        case 2:
            return 2;
    }
    return 0;
}");
    
    #Enum_Member_Name
    @DataDefs_v1 = (@DataDefs_v1, "enum type_test_enum_member_rename\n{\n    BRANCH_1=1,\n    BRANCH_2=2\n};");
    @DataDefs_v1 = (@DataDefs_v1, "int func_test_enum_member_rename(enum type_test_enum_member_rename param);");
    @Sources_v1 = (@Sources_v1,
"int func_test_enum_member_rename(enum type_test_enum_member_rename param)
{
    switch(param)
    {
        case 1:
            return 1;
        case 2:
            return 2;
    }
    return 0;
}");
    
    @DataDefs_v2 = (@DataDefs_v2, "enum type_test_enum_member_rename\n{\n    BRANCH_FIRST=1,\n    BRANCH_SECOND=1\n};");
    @DataDefs_v2 = (@DataDefs_v2, "int func_test_enum_member_rename(enum type_test_enum_member_rename param);");
    @Sources_v2 = (@Sources_v2,
"int func_test_enum_member_rename(enum type_test_enum_member_rename param)
{
    switch(param)
    {
        case 1:
            return 1;
        case 2:
            return 2;
    }
    return 0;
}");
    
    #Member_Type_And_Size
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_member_type_and_size\n{\npublic:\n    type_test_member_type_and_size func1(type_test_member_type_and_size param);\n    int i;\n    long j;\n    double k;\n    type_test_member_type_and_size* p;\n};");
    @Sources_v1 = (@Sources_v1, "type_test_member_type_and_size type_test_member_type_and_size::func1(type_test_member_type_and_size param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_member_type_and_size\n{\npublic:\n    type_test_member_type_and_size func1(type_test_member_type_and_size param);\n    long long i;\n    long j;\n    double k;\n    type_test_member_type_and_size* p;\n};");
    @Sources_v2 = (@Sources_v2, "type_test_member_type_and_size type_test_member_type_and_size::func1(type_test_member_type_and_size param)\n{\n    return param;\n}");
    
    #Member_Type
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_member_type\n{\npublic:\n    type_test_member_type func1(type_test_member_type param);\n    int i;\n    long j;\n    double k;\n    type_test_member_type* p;\n};");
    @Sources_v1 = (@Sources_v1, "type_test_member_type type_test_member_type::func1(type_test_member_type param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_member_type\n{\npublic:\n    type_test_member_type func1(type_test_member_type param);\n    float i;\n    long j;\n    double k;\n    type_test_member_type* p;\n};");
    @Sources_v2 = (@Sources_v2, "type_test_member_type type_test_member_type::func1(type_test_member_type param)\n{\n    return param;\n}");
    
    #Member_BaseType
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_member_basetype\n{\npublic:\n    type_test_member_basetype func1(type_test_member_basetype param);\n    int *i;\n    long j;\n    double k;\n    type_test_member_basetype* p;\n};");
    @Sources_v1 = (@Sources_v1, "type_test_member_basetype type_test_member_basetype::func1(type_test_member_basetype param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_member_basetype\n{\npublic:\n    type_test_member_basetype func1(type_test_member_basetype param);\n    long long *i;\n    long j;\n    double k;\n    type_test_member_basetype* p;\n};");
    @Sources_v2 = (@Sources_v2, "type_test_member_basetype type_test_member_basetype::func1(type_test_member_basetype param)\n{\n    return param;\n}");
    
    #Member_PointerLevel_And_Size
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_member_pointerlevel_and_size\n{\npublic:\n    type_test_member_pointerlevel_and_size func1(type_test_member_pointerlevel_and_size param);\n    long long i;\n    long j;\n    double k;\n    type_test_member_pointerlevel_and_size* p;\n};");
    @Sources_v1 = (@Sources_v1, "type_test_member_pointerlevel_and_size type_test_member_pointerlevel_and_size::func1(type_test_member_pointerlevel_and_size param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_member_pointerlevel_and_size\n{\npublic:\n    type_test_member_pointerlevel_and_size func1(type_test_member_pointerlevel_and_size param);\n    long long *i;\n    long j;\n    double k;\n    type_test_member_pointerlevel_and_size* p;\n};");
    @Sources_v2 = (@Sources_v2, "type_test_member_pointerlevel_and_size type_test_member_pointerlevel_and_size::func1(type_test_member_pointerlevel_and_size param)\n{\n    return param;\n}");
    
    #Member_PointerLevel
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_member_pointerlevel\n{\npublic:\n    type_test_member_pointerlevel func1(type_test_member_pointerlevel param);\n    int **i;\n    long j;\n    double k;\n    type_test_member_pointerlevel* p;\n};");
    @Sources_v1 = (@Sources_v1, "type_test_member_pointerlevel type_test_member_pointerlevel::func1(type_test_member_pointerlevel param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_member_pointerlevel\n{\npublic:\n    type_test_member_pointerlevel func1(type_test_member_pointerlevel param);\n    int *i;\n    long j;\n    double k;\n    type_test_member_pointerlevel* p;\n};");
    @Sources_v2 = (@Sources_v2, "type_test_member_pointerlevel type_test_member_pointerlevel::func1(type_test_member_pointerlevel param)\n{\n    return param;\n}");
    
    #Added_Interface (function)
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_added_interface\n{\npublic:\n    type_test_added_interface func1(type_test_added_interface param);\n    int i;\n    long j;\n    double k;\n    type_test_added_interface* p;\n};");
    @Sources_v1 = (@Sources_v1, "type_test_added_interface type_test_added_interface::func1(type_test_added_interface param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_added_interface\n{\npublic:\n    type_test_added_interface func1(type_test_added_interface param);\n    type_test_added_interface added_func(type_test_added_interface param);\n    int i;\n    long j;\n    double k;\n    type_test_added_interface* p;\n};");
    @DataDefs_v2 = (@DataDefs_v2, "int added_func_2(void *** param);");
    @Sources_v2 = (@Sources_v2, "type_test_added_interface type_test_added_interface::func1(type_test_added_interface param)\n{\n    return param;\n}");
    @Sources_v2 = (@Sources_v2, "type_test_added_interface type_test_added_interface::added_func(type_test_added_interface param)\n{\n    return param;\n}");
    @Sources_v2 = (@Sources_v2, "int added_func_2(void *** param)\n{\n    return 0;\n}");
    
    #Added_Interface (global variable)
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_added_variable\n{\npublic:\n    int func1(type_test_added_variable param);\n    int i;\n    long j;\n    double k;\n    type_test_added_variable* p;\n};");
    @Sources_v1 = (@Sources_v1, "int type_test_added_variable::func1(type_test_added_variable param)\n{\n    return i;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_added_variable\n{\npublic:\n    int func1(type_test_added_variable param);\n    static int i;\n    long j;\n    double k;\n    type_test_added_variable* p;\n};");
    @Sources_v2 = (@Sources_v2, "int type_test_added_variable::func1(type_test_added_variable param)\n{\n    return type_test_added_variable::i;\n}");
    @Sources_v2 = (@Sources_v2, "int type_test_added_variable::i=0;");
    
    #Withdrawn_Interface
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_withdrawn_interface\n{\npublic:\n    type_test_withdrawn_interface func1(type_test_withdrawn_interface param);\n    type_test_withdrawn_interface withdrawn_func(type_test_withdrawn_interface param);\n    int i;\n    long j;\n    double k;\n    type_test_withdrawn_interface* p;\n};");
    @DataDefs_v1 = (@DataDefs_v1, "int withdrawn_func_2(void *** param);");
    @Sources_v1 = (@Sources_v1, "type_test_withdrawn_interface type_test_withdrawn_interface::func1(type_test_withdrawn_interface param)\n{\n    return param;\n}");
    @Sources_v1 = (@Sources_v1, "type_test_withdrawn_interface type_test_withdrawn_interface::withdrawn_func(type_test_withdrawn_interface param)\n{\n    return param;\n}");
    @Sources_v1 = (@Sources_v1, "int withdrawn_func_2(void *** param)\n{\n    return 0;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_withdrawn_interface\n{\npublic:\n    type_test_withdrawn_interface func1(type_test_withdrawn_interface param);\n    int i;\n    long j;\n    double k;\n    type_test_withdrawn_interface* p;\n};");
    @Sources_v2 = (@Sources_v2, "type_test_withdrawn_interface type_test_withdrawn_interface::func1(type_test_withdrawn_interface param)\n{\n    return param;\n}");
    
    #Function_Become_Static
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_become_static\n{\npublic:\n    type_test_become_static func_become_static(type_test_become_static param);\n    int **i;\n    long j;\n    double k;\n    type_test_become_static* p;\n};");
    @Sources_v1 = (@Sources_v1, "type_test_become_static type_test_become_static::func_become_static(type_test_become_static param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_become_static\n{\npublic:\n    static type_test_become_static func_become_static(type_test_become_static param);\n    int **i;\n    long j;\n    double k;\n    type_test_become_static* p;\n};");
    @Sources_v2 = (@Sources_v2, "type_test_become_static type_test_become_static::func_become_static(type_test_become_static param)\n{\n    return param;\n}");
    
    #Function_Become_NonStatic
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_become_nonstatic\n{\npublic:\n    static type_test_become_nonstatic func_become_nonstatic(type_test_become_nonstatic param);\n    int **i;\n    long j;\n    double k;\n    type_test_become_nonstatic* p;\n};");
    @Sources_v1 = (@Sources_v1, "type_test_become_nonstatic type_test_become_nonstatic::func_become_nonstatic(type_test_become_nonstatic param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_become_nonstatic\n{\npublic:\n    type_test_become_nonstatic func_become_nonstatic(type_test_become_nonstatic param);\n    int **i;\n    long j;\n    double k;\n    type_test_become_nonstatic* p;\n};");
    @Sources_v2 = (@Sources_v2, "type_test_become_nonstatic type_test_become_nonstatic::func_become_nonstatic(type_test_become_nonstatic param)\n{\n    return param;\n}");
    
    #Parameter_Type_And_Size
    @DataDefs_v1 = (@DataDefs_v1, "int func_parameter_type_and_size(int param, int other_param);");
    @Sources_v1 = (@Sources_v1, "int func_parameter_type_and_size(int param, int other_param)\n{\n    return other_param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "int func_parameter_type_and_size(long long param, int other_param);");
    @Sources_v2 = (@Sources_v2, "int func_parameter_type_and_size(long long param, int other_param)\n{\n    return other_param;\n}");
    
    #Parameter_Type
    @DataDefs_v1 = (@DataDefs_v1, "int func_parameter_type(int param, int other_param);");
    @Sources_v1 = (@Sources_v1, "int func_parameter_type(int param, int other_param)\n{\n    return other_param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "int func_parameter_type(float param, int other_param);");
    @Sources_v2 = (@Sources_v2, "int func_parameter_type(float param, int other_param)\n{\n    return other_param;\n}");
    
    #Parameter_BaseType
    @DataDefs_v1 = (@DataDefs_v1, "int func_parameter_basetypechange(int *param);");
    @Sources_v1 = (@Sources_v1, "int func_parameter_basetypechange(int *param)\n{\n    return sizeof(*param);\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "int func_parameter_basetypechange(long long *param);");
    @Sources_v2 = (@Sources_v2, "int func_parameter_basetypechange(long long *param)\n{\n    return sizeof(*param);\n}");
    
    #Parameter_PointerLevel_And_Size
    @DataDefs_v1 = (@DataDefs_v1, "long long func_parameter_pointerlevel_and_size(long long param);");
    @Sources_v1 = (@Sources_v1, "long long func_parameter_pointerlevel_and_size(long long param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "long long func_parameter_pointerlevel_and_size(long long *param);");
    @Sources_v2 = (@Sources_v2, "long long func_parameter_pointerlevel_and_size(long long *param)\n{\n    return param[5];\n}");
    
    #Parameter_PointerLevel
    @DataDefs_v1 = (@DataDefs_v1, "int func_parameter_pointerlevel(int *param);");
    @Sources_v1 = (@Sources_v1, "int func_parameter_pointerlevel(int *param)\n{\n    return param[5];\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "int func_parameter_pointerlevel(int **param);");
    @Sources_v2 = (@Sources_v2, "int func_parameter_pointerlevel(int **param)\n{\n    return param[5][5];\n}");
    
    #Return_Type_And_Size
    @DataDefs_v1 = (@DataDefs_v1, "int func_return_type_and_size(int param);");
    @Sources_v1 = (@Sources_v1, "int func_return_type_and_size(int param)\n{\n    return 2^(sizeof(int)*8-1)-1;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "long long func_return_type_and_size(int param);");
    @Sources_v2 = (@Sources_v2, "long long func_return_type_and_size(int param)\n{\n    return 2^(sizeof(long long)*8-1)-1;\n}");
    
    #Return_Type
    @DataDefs_v1 = (@DataDefs_v1, "int func_return_type(int param);");
    @Sources_v1 = (@Sources_v1, "int func_return_type(int param)\n{\n    return 2^(sizeof(int)*8-1)-1;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "float func_return_type(int param);");
    @Sources_v2 = (@Sources_v2, "float func_return_type(int param)\n{\n    return 0.7;\n}");
    
    #Return_BaseType
    @DataDefs_v1 = (@DataDefs_v1, "int *func_return_basetype(int param);");
    @Sources_v1 = (@Sources_v1, "int *func_return_basetype(int param)\n{\n    int *x = new int[10];\n    return x;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "long long *func_return_basetype(int param);");
    @Sources_v2 = (@Sources_v2, "long long *func_return_basetype(int param)\n{\n    long long *x = new long long[10];\n    return x;\n}");
    
    #Return_PointerLevel_And_Size
    @DataDefs_v1 = (@DataDefs_v1, "long long func_return_pointerlevel_and_size(int param);");
    @Sources_v1 = (@Sources_v1, "long long func_return_pointerlevel_and_size(int param)\n{\n    return 100;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "long long *func_return_pointerlevel_and_size(int param);");
    @Sources_v2 = (@Sources_v2, "long long *func_return_pointerlevel_and_size(int param)\n{\n    long long* x = new long long[10];\n    return x;\n}");
    
    #Return_PointerLevel
    @DataDefs_v1 = (@DataDefs_v1, "int* func_return_pointerlevel(int param);");
    @Sources_v1 = (@Sources_v1, "int* func_return_pointerlevel(int param)\n{\n    int* x = new int[10];\n    return x;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "int **func_return_pointerlevel(int param);");
    @Sources_v2 = (@Sources_v2, "int **func_return_pointerlevel(int param)\n{\n    int** x = new int*[10];\n    return x;\n}");
    
    #Typedef to anon struct
    @DataDefs_v1 = (@DataDefs_v1, "
typedef struct
{
public:
    int i;
    long j;
    double k;
} type_test_anon_typedef;");
    @Sources_v1 = (@Sources_v1, "int func_test_anon_typedef(type_test_anon_typedef param)\n{\n    return 0;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "
typedef struct
{
public:
    int i;
    long j;
    double k;
    union {
        int dummy[256];
        struct {
            char q_skiptable[256];
            const char *p;
            int l;
        } p;
    };
} type_test_anon_typedef;");
    @Sources_v2 = (@Sources_v2, "int func_test_anon_typedef(type_test_anon_typedef param)\n{\n    return 0;\n}");
    
    #Opaque Types
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_opaque\n{\npublic:\n    virtual type_test_opaque func1(type_test_opaque param);\n    int i;\n    long j;\n    double k;\n    type_test_opaque* p;\n};");
    @Sources_v1 = (@Sources_v1, "type_test_opaque type_test_opaque::func1(type_test_opaque param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_opaque\n{\npublic:\n    virtual type_test_opaque func1(type_test_opaque param);\n    int i;\n    long j;\n    double k;\n    type_test_opaque* p;\n    int added_member;\n};");
    @Sources_v2 = (@Sources_v2, "type_test_opaque type_test_opaque::func1(type_test_opaque param)\n{\n    return param;\n}");
    
    #Internal Function
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_internal\n{\npublic:\n    virtual type_test_internal func1(type_test_internal param);\n    int i;\n    long j;\n    double k;\n    type_test_internal* p;\n};");
    @Sources_v1 = (@Sources_v1, "type_test_internal type_test_internal::func1(type_test_internal param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_internal\n{\npublic:\n    virtual type_test_internal func1(type_test_internal param);\n    int i;\n    long j;\n    double k;\n    type_test_internal* p;\n    int added_member;\n};");
    @Sources_v2 = (@Sources_v2, "type_test_internal type_test_internal::func1(type_test_internal param)\n{\n    return param;\n}");
    
    create_TestSuite("abi_changes_test_cpp", "C++", join("\n\n", @DataDefs_v1), join("\n\n", @Sources_v1), join("\n\n", @DataDefs_v2), join("\n\n", @Sources_v2), "type_test_opaque", "_ZN18type_test_internal5func1ES_");
}

sub testSystem_c()
{
    print "\ntesting on C library changes\n";
    my @DataDefs_v1 = ();
    my @Sources_v1 = ();
    my @DataDefs_v2 = ();
    my @Sources_v2 = ();
    
    #Size
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_size\n{\n    long long i[5];\n    long j;\n    double k;\n    struct type_test_size* p;\n};");
    @DataDefs_v1 = (@DataDefs_v1, "int func_test_type_size(struct type_test_size param, int param_2);");
    @Sources_v1 = (@Sources_v1, "int func_test_type_size(struct type_test_size param, int param_2)\n{\n    return param_2;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_size\n{\n    long long i[5];\n    long long j;\n    double k;\n    struct type_test_size* p;\n};");
    @DataDefs_v2 = (@DataDefs_v2, "int func_test_type_size(struct type_test_size param, int param_2);");
    @Sources_v2 = (@Sources_v2, "int func_test_type_size(struct type_test_size param, int param_2)\n{\n    return param_2;\n}");
    
    #Added_Member
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_added_member\n{\n    int i;\n    long j;\n    double k;\n    struct type_test_added_member* p;\n};");
    @DataDefs_v1 = (@DataDefs_v1, "int func_test_added_member(struct type_test_added_member param, int param_2);");
    @Sources_v1 = (@Sources_v1, "int func_test_added_member(struct type_test_added_member param, int param_2)\n{\n    return param_2;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_added_member\n{\n    int i;\n    long j;\n    double k;\n    struct type_test_added_member* p;\n    int added_member;\n};");
    @DataDefs_v2 = (@DataDefs_v2, "int func_test_added_member(struct type_test_added_member param, int param_2);");
    @Sources_v2 = (@Sources_v2, "int func_test_added_member(struct type_test_added_member param, int param_2)\n{\n    return param_2;\n}");
    
    #Added_Middle_Member
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_added_middle_member\n{\n    int i;\n    long j;\n    double k;\n    struct type_test_added_member* p;\n};");
    @DataDefs_v1 = (@DataDefs_v1, "int func_test_added_middle_member(struct type_test_added_middle_member param, int param_2);");
    @Sources_v1 = (@Sources_v1, "int func_test_added_middle_member(struct type_test_added_middle_member param, int param_2)\n{\n    return param_2;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_added_middle_member\n{\n    int i;\n    int added_middle_member;\n    long j;\n    double k;\n    struct type_test_added_member* p;\n};");
    @DataDefs_v2 = (@DataDefs_v2, "int func_test_added_middle_member(struct type_test_added_middle_member param, int param_2);");
    @Sources_v2 = (@Sources_v2, "int func_test_added_middle_member(struct type_test_added_middle_member param, int param_2)\n{\n    return param_2;\n}");
    
    #Member_Rename
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_member_rename\n{\n    long i;\n    long j;\n    double k;\n    struct type_test_member_rename* p;\n};");
    @DataDefs_v1 = (@DataDefs_v1, "int func_test_member_rename(struct type_test_member_rename param, int param_2);");
    @Sources_v1 = (@Sources_v1, "int func_test_member_rename(struct type_test_member_rename param, int param_2)\n{\n    return param_2;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_member_rename\n{\n    long* renamed_member;\n    long j;\n    double k;\n    struct type_test_member_rename* p;\n};");
    @DataDefs_v2 = (@DataDefs_v2, "int func_test_member_rename(struct type_test_member_rename param, int param_2);");
    @Sources_v2 = (@Sources_v2, "int func_test_member_rename(struct type_test_member_rename param, int param_2)\n{\n    return param_2;\n}");
    
    #Withdrawn_Member_And_Size
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_withdrawn_member\n{\n    int i;\n    long j;\n    double k;\n    struct type_test_withdrawn_member* p;\n    int withdrawn_member;\n};");
    @DataDefs_v1 = (@DataDefs_v1, "int func_test_withdrawn_member(struct type_test_withdrawn_member param, int param_2);");
    @Sources_v1 = (@Sources_v1, "int func_test_withdrawn_member(struct type_test_withdrawn_member param, int param_2)\n{\n    return param_2;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_withdrawn_member\n{\n    int i;\n    long j;\n    double k;\n    struct type_test_withdrawn_member* p;\n};");
    @DataDefs_v2 = (@DataDefs_v2, "int func_test_withdrawn_member(struct type_test_withdrawn_member param, int param_2);");
    @Sources_v2 = (@Sources_v2, "int func_test_withdrawn_member(struct type_test_withdrawn_member param, int param_2)\n{\n    return param_2;\n}");
    
    #Withdrawn_Middle_Member
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_withdrawn_middle_member\n{\n    int i;\n    int withdrawn_middle_member;\n    long j;\n    double k;\n    struct type_test_withdrawn_middle_member* p;\n};");
    @DataDefs_v1 = (@DataDefs_v1, "int func_test_withdrawn_middle_member(struct type_test_withdrawn_middle_member param, int param_2);");
    @Sources_v1 = (@Sources_v1, "int func_test_withdrawn_middle_member(struct type_test_withdrawn_middle_member param, int param_2)\n{\n    return param_2;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_withdrawn_middle_member\n{\n    int i;\n    long j;\n    double k;\n    struct type_test_withdrawn_middle_member* p;\n};");
    @DataDefs_v2 = (@DataDefs_v2, "int func_test_withdrawn_middle_member(struct type_test_withdrawn_middle_member param, int param_2);");
    @Sources_v2 = (@Sources_v2, "int func_test_withdrawn_middle_member(struct type_test_withdrawn_middle_member param, int param_2)\n{\n    return param_2;\n}");
    
    #Enum_Member_Value
    @DataDefs_v1 = (@DataDefs_v1, "enum type_test_enum_member_value_change\n{\n    MEMBER_1=1,\n    MEMBER_2=2\n};");
    @DataDefs_v1 = (@DataDefs_v1, "int func_test_enum_member_value_change(enum type_test_enum_member_value_change param);");
    @Sources_v1 = (@Sources_v1,
"int func_test_enum_member_value_change(enum type_test_enum_member_value_change param)
{
    switch(param)
    {
        case 1:
            return 1;
        case 2:
            return 2;
    }
    return 0;
}");
    
    @DataDefs_v2 = (@DataDefs_v2, "enum type_test_enum_member_value_change\n{\n    MEMBER_1=2,\n    MEMBER_2=1\n};");
    @DataDefs_v2 = (@DataDefs_v2, "int func_test_enum_member_value_change(enum type_test_enum_member_value_change param);");
    @Sources_v2 = (@Sources_v2,
"int func_test_enum_member_value_change(enum type_test_enum_member_value_change param)
{
    switch(param)
    {
        case 1:
            return 1;
        case 2:
            return 2;
    }
    return 0;
}");
    
    #Enum_Member_Name
    @DataDefs_v1 = (@DataDefs_v1, "enum type_test_enum_member_rename\n{\n    BRANCH_1=1,\n    BRANCH_2=2\n};");
    @DataDefs_v1 = (@DataDefs_v1, "int func_test_enum_member_rename(enum type_test_enum_member_rename param);");
    @Sources_v1 = (@Sources_v1,
"int func_test_enum_member_rename(enum type_test_enum_member_rename param)
{
    switch(param)
    {
        case 1:
            return 1;
        case 2:
            return 2;
    }
    return 0;
}");
    
    @DataDefs_v2 = (@DataDefs_v2, "enum type_test_enum_member_rename\n{\n    BRANCH_FIRST=1,\n    BRANCH_SECOND=1\n};");
    @DataDefs_v2 = (@DataDefs_v2, "int func_test_enum_member_rename(enum type_test_enum_member_rename param);");
    @Sources_v2 = (@Sources_v2,
"int func_test_enum_member_rename(enum type_test_enum_member_rename param)
{
    switch(param)
    {
        case 1:
            return 1;
        case 2:
            return 2;
    }
    return 0;
}");
    
    #Member_Type_And_Size
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_member_type_and_size\n{\n    int i;\n    long j;\n    double k;\n    struct type_test_member_type_and_size* p;\n};");
    @DataDefs_v1 = (@DataDefs_v1, "int func_test_member_type_and_size(struct type_test_member_type_and_size param, int param_2);");
    @Sources_v1 = (@Sources_v1, "int func_test_member_type_and_size(struct type_test_member_type_and_size param, int param_2)\n{\n    return param_2;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_member_type_and_size\n{\n    int i;\n    long j;\n    long double k;\n    struct type_test_member_type_and_size* p;\n};");
    @DataDefs_v2 = (@DataDefs_v2, "int func_test_member_type_and_size(struct type_test_member_type_and_size param, int param_2);");
    @Sources_v2 = (@Sources_v2, "int func_test_member_type_and_size(struct type_test_member_type_and_size param, int param_2)\n{\n    return param_2;\n}");
    
    #Member_Type
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_member_type\n{\n    int i;\n    long j;\n    double k;\n    struct type_test_member_type* p;\n};");
    @DataDefs_v1 = (@DataDefs_v1, "int func_test_member_type(struct type_test_member_type param, int param_2);");
    @Sources_v1 = (@Sources_v1, "int func_test_member_type(struct type_test_member_type param, int param_2)\n{\n    return param_2;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_member_type\n{\n    float i;\n    long j;\n    double k;\n    struct type_test_member_type* p;\n};");
    @DataDefs_v2 = (@DataDefs_v2, "int func_test_member_type(struct type_test_member_type param, int param_2);");
    @Sources_v2 = (@Sources_v2, "int func_test_member_type(struct type_test_member_type param, int param_2)\n{\n    return param_2;\n}");
    
    #Member_BaseType
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_member_basetype\n{\n    int i;\n    long *j;\n    double k;\n    struct type_test_member_basetype* p;\n};");
    @DataDefs_v1 = (@DataDefs_v1, "int func_test_member_basetype(struct type_test_member_basetype param, int param_2);");
    @Sources_v1 = (@Sources_v1, "int func_test_member_basetype(struct type_test_member_basetype param, int param_2)\n{\n    return param_2;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_member_basetype\n{\n    int i;\n    long long *j;\n    double k;\n    struct type_test_member_basetype* p;\n};");
    @DataDefs_v2 = (@DataDefs_v2, "int func_test_member_basetype(struct type_test_member_basetype param, int param_2);");
    @Sources_v2 = (@Sources_v2, "int func_test_member_basetype(struct type_test_member_basetype param, int param_2)\n{\n    return param_2;\n}");
    
    #Member_PointerLevel_And_Size
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_member_pointerlevel_and_size\n{\n    int i;\n    long long j;\n    double k;\n    struct type_test_member_pointerlevel_and_size* p;\n};");
    @DataDefs_v1 = (@DataDefs_v1, "int func_test_member_pointerlevel_and_size(struct type_test_member_pointerlevel_and_size param, int param_2);");
    @Sources_v1 = (@Sources_v1, "int func_test_member_pointerlevel_and_size(struct type_test_member_pointerlevel_and_size param, int param_2)\n{\n    return param_2;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_member_pointerlevel_and_size\n{\n    int i;\n    long long *j;\n    double k;\n    struct type_test_member_pointerlevel_and_size* p;\n};");
    @DataDefs_v2 = (@DataDefs_v2, "int func_test_member_pointerlevel_and_size(struct type_test_member_pointerlevel_and_size param, int param_2);");
    @Sources_v2 = (@Sources_v2, "int func_test_member_pointerlevel_and_size(struct type_test_member_pointerlevel_and_size param, int param_2)\n{\n    return param_2;\n}");
    
    #Member_PointerLevel
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_member_pointerlevel\n{\n    int i;\n    long *j;\n    double k;\n    struct type_test_member_pointerlevel* p;\n};");
    @DataDefs_v1 = (@DataDefs_v1, "int func_test_member_pointerlevel(struct type_test_member_pointerlevel param, int param_2);");
    @Sources_v1 = (@Sources_v1, "int func_test_member_pointerlevel(struct type_test_member_pointerlevel param, int param_2)\n{\n    return param_2;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_member_pointerlevel\n{\n    int i;\n    long **j;\n    double k;\n    struct type_test_member_pointerlevel* p;\n};");
    @DataDefs_v2 = (@DataDefs_v2, "int func_test_member_pointerlevel(struct type_test_member_pointerlevel param, int param_2);");
    @Sources_v2 = (@Sources_v2, "int func_test_member_pointerlevel(struct type_test_member_pointerlevel param, int param_2)\n{\n    return param_2;\n}");
    
    #Added_Interface
    @DataDefs_v2 = (@DataDefs_v2, "int added_func(int param);");
    @Sources_v2 = (@Sources_v2, "int added_func(int param)\n{\n    return param;\n}");
    
    #Withdrawn_Interface
    @DataDefs_v1 = (@DataDefs_v1, "int withdrawn_func(int param);");
    @Sources_v1 = (@Sources_v1, "int withdrawn_func(int param)\n{\n    return param;\n}");
    
    #Parameter_Type_And_Size
    @DataDefs_v1 = (@DataDefs_v1, "int func_parameter_type_and_size(int param, int other_param);");
    @Sources_v1 = (@Sources_v1, "int func_parameter_type_and_size(int param, int other_param)\n{\n    return other_param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "int func_parameter_type_and_size(long long param, int other_param);");
    @Sources_v2 = (@Sources_v2, "int func_parameter_type_and_size(long long param, int other_param)\n{\n    return other_param;\n}");
    
    #Parameter_Type
    @DataDefs_v1 = (@DataDefs_v1, "int func_parameter_type(int param, int other_param);");
    @Sources_v1 = (@Sources_v1, "int func_parameter_type(int param, int other_param)\n{\n    return other_param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "int func_parameter_type(float param, int other_param);");
    @Sources_v2 = (@Sources_v2, "int func_parameter_type(float param, int other_param)\n{\n    return other_param;\n}");
    
    #Parameter_BaseType
    @DataDefs_v1 = (@DataDefs_v1, "int func_parameter_basetypechange(int *param);");
    @Sources_v1 = (@Sources_v1, "int func_parameter_basetypechange(int *param)\n{\n    return sizeof(*param);\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "int func_parameter_basetypechange(long long *param);");
    @Sources_v2 = (@Sources_v2, "int func_parameter_basetypechange(long long *param)\n{\n    return sizeof(*param);\n}");
    
    #Parameter_PointerLevel_And_Size
    @DataDefs_v1 = (@DataDefs_v1, "long long func_parameter_pointerlevel_and_size(long long param);");
    @Sources_v1 = (@Sources_v1, "long long func_parameter_pointerlevel_and_size(long long param)\n{\n    return param;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "long long func_parameter_pointerlevel_and_size(long long *param);");
    @Sources_v2 = (@Sources_v2, "long long func_parameter_pointerlevel_and_size(long long *param)\n{\n    return param[5];\n}");
    
    #Parameter_PointerLevel
    @DataDefs_v1 = (@DataDefs_v1, "int func_parameter_pointerlevel(int *param);");
    @Sources_v1 = (@Sources_v1, "int func_parameter_pointerlevel(int *param)\n{\n    return param[5];\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "int func_parameter_pointerlevel(int **param);");
    @Sources_v2 = (@Sources_v2, "int func_parameter_pointerlevel(int **param)\n{\n    return param[5][5];\n}");
    
    #Return_Type_And_Size
    @DataDefs_v1 = (@DataDefs_v1, "int func_return_type_and_size(int param);");
    @Sources_v1 = (@Sources_v1, "int func_return_type_and_size(int param)\n{\n    return 2^(sizeof(int)*8-1)-1;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "long long func_return_type_and_size(int param);");
    @Sources_v2 = (@Sources_v2, "long long func_return_type_and_size(int param)\n{\n    return 2^(sizeof(long long)*8-1)-1;\n}");
    
    #Return_Type
    @DataDefs_v1 = (@DataDefs_v1, "int func_return_type(int param);");
    @Sources_v1 = (@Sources_v1, "int func_return_type(int param)\n{\n    return 2^(sizeof(int)*8-1)-1;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "float func_return_type(int param);");
    @Sources_v2 = (@Sources_v2, "float func_return_type(int param)\n{\n    return 0.7;\n}");
    
    #Return_BaseType
    @DataDefs_v1 = (@DataDefs_v1, "int *func_return_basetypechange(int param);");
    @Sources_v1 = (@Sources_v1, "int *func_return_basetypechange(int param)\n{\n    int *x = (int*)malloc(10*sizeof(int));\n    *x = 2^(sizeof(int)*8-1)-1;\n    return x;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "long long *func_return_basetypechange(int param);");
    @Sources_v2 = (@Sources_v2, "long long *func_return_basetypechange(int param)\n{\n    long long *x = (long long*)malloc(10*sizeof(long long));\n    *x = 2^(sizeof(long long)*8-1)-1;\n    return x;\n}");
    
    #Return_PointerLevel_And_Size
    @DataDefs_v1 = (@DataDefs_v1, "long long func_return_pointerlevel_and_size(int param);");
    @Sources_v1 = (@Sources_v1, "long long func_return_pointerlevel_and_size(int param)\n{\n    return 100;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "long long *func_return_pointerlevel_and_size(int param);");
    @Sources_v2 = (@Sources_v2, "long long *func_return_pointerlevel_and_size(int param)\n{\n    long long *x = (long long*)malloc(10*sizeof(long long));\n    *x = 2^(sizeof(long long)*8-1)-1;\n    return x;\n}");
    
    #Return_PointerLevel
    @DataDefs_v1 = (@DataDefs_v1, "long long *func_return_pointerlevel(int param);");
    @Sources_v1 = (@Sources_v1, "long long *func_return_pointerlevel(int param)\n{\n    long long *x = (long long*)malloc(10*sizeof(long long));\n    *x = 2^(sizeof(long long)*8-1)-1;\n    return x;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "long long **func_return_pointerlevel(int param);");
    @Sources_v2 = (@Sources_v2, "long long **func_return_pointerlevel(int param)\n{\n    long long *x = (long long*)malloc(10*sizeof(long long));\n    *x = 2^(sizeof(long long)*8-1)-1;\n    long *y = (long*)malloc(sizeof(long long));\n    *y=(long)&x;\n    return (long long **)y;\n}");
    
    #Opaque Types
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_opaque\n{\n    long long i[5];\n    long j;\n    double k;\n    struct type_test_opaque* p;\n};");
    @DataDefs_v1 = (@DataDefs_v1, "int func_test_opaque(struct type_test_opaque param, int param_2);");
    @Sources_v1 = (@Sources_v1, "int func_test_opaque(struct type_test_opaque param, int param_2)\n{\n    return param_2;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_opaque\n{\n    long long i[5];\n    long long j;\n    double k;\n    struct type_test_opaque* p;\n};");
    @DataDefs_v2 = (@DataDefs_v2, "int func_test_opaque(struct type_test_opaque param, int param_2);");
    @Sources_v2 = (@Sources_v2, "int func_test_opaque(struct type_test_opaque param, int param_2)\n{\n    return param_2;\n}");
    
    #Internal Function
    @DataDefs_v1 = (@DataDefs_v1, "struct type_test_internal\n{\n    long long i[5];\n    long j;\n    double k;\n    struct type_test_internal* p;\n};");
    @DataDefs_v1 = (@DataDefs_v1, "int func_test_internal(struct type_test_internal param, int param_2);");
    @Sources_v1 = (@Sources_v1, "int func_test_internal(struct type_test_internal param, int param_2)\n{\n    return param_2;\n}");
    
    @DataDefs_v2 = (@DataDefs_v2, "struct type_test_internal\n{\n    long long i[5];\n    long long j;\n    double k;\n    struct type_test_internal* p;\n};");
    @DataDefs_v2 = (@DataDefs_v2, "int func_test_internal(struct type_test_internal param, int param_2);");
    @Sources_v2 = (@Sources_v2, "int func_test_internal(struct type_test_internal param, int param_2)\n{\n    return param_2;\n}");
    
    create_TestSuite("abi_changes_test_c", "C", join("\n\n", @DataDefs_v1), join("\n\n", @Sources_v1), join("\n\n", @DataDefs_v2), join("\n\n", @Sources_v2), "type_test_opaque", "func_test_internal");
}

sub create_TestSuite($$$$$$$$)
{
    my $Dir = $_[0];
    my $Lang = $_[1];
    my $DataDefs_v1 = $_[2];
    my $Sources_v1 = $_[3];
    my $DataDefs_v2 = $_[4];
    my $Sources_v2 = $_[5];
    my $Opaque = $_[6];
    my $Private = $_[7];
    
    my $Ext = ($Lang eq "C++")?"cpp":"c";
    my $Gcc = ($Lang eq "C++")?"g++":"gcc";
    
    #Creating test suite
    my $Path_v1 = "$Dir/lib_abi_changes_test.v1";
    my $Path_v2 = "$Dir/lib_abi_changes_test.v2";
    
    `rm -fr $Path_v1 $Path_v2`;
    `mkdir -p $Path_v1 $Path_v2`;
    
    open(DATA_DEFS_1, ">$Path_v1/lib_abi_changes_test.h");
    print DATA_DEFS_1 "#include <stdlib.h>\n".$DataDefs_v1."\n";
    close(DATA_DEFS_1);
    
    open(SOURCES_1, ">$Path_v1/lib_abi_changes_test.$Ext");
    print SOURCES_1 "#include \"lib_abi_changes_test.h\"\n".$Sources_v1."\n";
    close(SOURCES_1);
    
    open(DATA_DEFS_2, ">$Path_v2/lib_abi_changes_test.h");
    print DATA_DEFS_2 "#include <stdlib.h>\n".$DataDefs_v2."\n";
    close(DATA_DEFS_2);
    
    open(SOURCES_2, ">$Path_v2/lib_abi_changes_test.$Ext");
    print SOURCES_2 "#include \"lib_abi_changes_test.h\"\n".$Sources_v2."\n";
    close(SOURCES_2);
    
    open(DESCRIPTOR_1, ">$Dir/descriptor.v1");
    print DESCRIPTOR_1 "<version>\n    1.0.0\n  </version>\n<headers>\n    lib_abi_changes_test.v1/\n  </headers>\n<libs>\n    lib_abi_changes_test.v1/\n  </libs>\n<opaque_types>\n    $Opaque\n  </opaque_types>\n<internal_functions>\n    \n  $Private</internal_functions>\n";
    close(DESCRIPTOR_1);
    
    open(DESCRIPTOR_2, ">$Dir/descriptor.v2");
    print DESCRIPTOR_2 "<version>\n    2.0.0\n  </version>\n<headers>\n    lib_abi_changes_test.v2/\n  </headers>\n<libs>\n    lib_abi_changes_test.v2/\n  </libs>\n<opaque_types>\n    $Opaque\n  </opaque_types>\n<internal_functions>\n    \n  $Private</internal_functions>\n";
    close(DESCRIPTOR_2);
    
    system("$Gcc $Path_v1/lib_abi_changes_test.h");
    if($?)
    {
        print "can't compile $Path_v1/lib_abi_changes_test.h\n";
        return;
    }
    system("$Gcc -shared $Path_v1/lib_abi_changes_test.$Ext -o $Path_v1/lib_abi_changes_test.so");
    if($?)
    {
        print "can't compile $Path_v1/lib_abi_changes_test.$Ext\n";
        return;
    }
    system("$Gcc $Path_v2/lib_abi_changes_test.h");
    if($?)
    {
        print "can't compile $Path_v2/lib_abi_changes_test.h\n";
        return;
    }
    system("$Gcc -shared $Path_v2/lib_abi_changes_test.$Ext -o $Path_v2/lib_abi_changes_test.so");
    if($?)
    {
        print "can't compile $Path_v2/lib_abi_changes_test.$Ext\n";
        return;
    }
    
    #Running abi-compliance-checker
    my $Tool_Dir = get_Dir_ByPath($0);
    $Tool_Dir .= "/" if($Tool_Dir);
    system("$0 -l lib_$Dir -d1 ".$Tool_Dir."$Dir/descriptor.v1 -d2 ".$Tool_Dir."$Dir/descriptor.v2");
}

sub getArch()
{
    my $Arch;
    $Arch = $ENV{'CPU'};
    if(not $Arch)
    {
        $Arch = `uname -p`;
        chomp($Arch);
    }
    $Arch = "ia32" if($Arch =~ /i[3-7]86/);
    return $Arch;
}

sub get_Report_Header()
{
    my $Report_Header = "<h1>ABI compliance report for library <span style='color:Blue;'>$TargetLibraryName </span> update from <span style='color:Red;'>$Descriptor{1}{'Version'}</span> to <span style='color:Red;'>$Descriptor{2}{'Version'}</span> version on <span style='color:Blue;'>".getArch()."</span></h1>\n";
    return "<!--Header-->\n".$Report_Header."<!--Header_End-->\n";
}

sub get_SourceInfo()
{
    my $CheckedHeaders = "<!--Checked_Headers-->\n<a name='Checked_Headers'></a><h2 style='margin-bottom:0px;padding-bottom:0px;'>Checked headers (".keys(%{$HeaderDestination{1}}).")</h2><hr/>\n";
    foreach my $Header (sort keys(%{$HeaderDestination{1}}))
    {
        $CheckedHeaders .= "<span class='header_name' style='padding-left:10px;color:#333333;'>$Header</span><br/>\n";
    }
    $CheckedHeaders .= "<!--Checked_Headers_End--><br/><a style='font-size:11px;' href='#Top'>to the top</a><br/>\n";
    my $CheckedLibs = "<!--Checked_Libs-->\n<a name='Checked_Libs'></a><h2 style='margin-bottom:0px;padding-bottom:0px;'>Checked shared libraries (".keys(%{$Library{1}}).")</h2><hr/>\n";
    foreach my $Library (sort keys(%{$Library{1}}))
    {
        $CheckedLibs .= "<span class='solib_name' style='padding-left:10px;color:#333333;'>$Library</span><br/>\n";
    }
    $CheckedLibs .= "<!--Checked_Libs_End--><br/><a style='font-size:11px;' href='#Top'>to the top</a><br/>\n";
    return $CheckedHeaders.$CheckedLibs;
}

sub get_Summary()
{
    my %TypeChanges;
    foreach my $FuncName (sort keys(%CompatProblems))
    {
        foreach my $Kind (keys(%{$CompatProblems{$FuncName}}))
        {
            if($TypeProblems_Kind{$Kind})
            {
                foreach my $Location (keys(%{$CompatProblems{$FuncName}{$Kind}}))
                {
                    my $Type_Name = $CompatProblems{$FuncName}{$Kind}{$Location}{'Type_Name'};
                    my $Priority = $CompatProblems{$FuncName}{$Kind}{$Location}{'Priority'};
                    %{$TypeChanges{$Type_Name}{$Kind}} = %{$CompatProblems{$FuncName}{$Kind}{$Location}};
                    $TypeChanges{$Type_Name}{$Kind}{'Priority'} = max_priority($TypeChanges{$Type_Name}{$Kind}{'Priority'}, $Priority);
                }
            }
        }
    }
    my ($Added, $Withdrawn, $I_Problems_High, $I_Problems_Medium, $I_Problems_Low, $T_Problems_High, $T_Problems_Medium, $T_Problems_Low) = (0,0,0,0,0,0,0,0);
    foreach my $FuncName (sort keys(%CompatProblems))
    {
        foreach my $Kind (sort keys(%{$CompatProblems{$FuncName}}))
        {
            if($InterfaceProblems_Kind{$Kind})
            {
                foreach my $Location (sort keys(%{$CompatProblems{$FuncName}{$Kind}}))
                {
                    if($Kind eq "Added_Interface")
                    {
                        $Added += 1;
                    }
                    elsif($Kind eq "Withdrawn_Interface")
                    {
                        $Withdrawn += 1;
                    }
                    else
                    {
                        if($CompatProblems{$FuncName}{$Kind}{$Location}{'Priority'} eq "High")
                        {
                            $I_Problems_High += 1;
                        }
                        elsif($CompatProblems{$FuncName}{$Kind}{$Location}{'Priority'} eq "Medium")
                        {
                            $I_Problems_Medium += 1;
                        }
                        elsif($CompatProblems{$FuncName}{$Kind}{$Location}{'Priority'} eq "Low")
                        {
                            $I_Problems_Low += 1;
                        }
                    }
                }
            }
        }
    }
    foreach my $TypeName (sort keys(%TypeChanges))
    {
        foreach my $Kind (sort keys(%{$TypeChanges{$TypeName}}))
        {
            if($TypeChanges{$TypeName}{$Kind}{'Priority'} eq "High")
            {
                $T_Problems_High += 1;
            }
            elsif($TypeChanges{$TypeName}{$Kind}{'Priority'} eq "Medium")
            {
                $T_Problems_Medium += 1;
            }
            elsif($TypeChanges{$TypeName}{$Kind}{'Priority'} eq "Low")
            {
                $T_Problems_Low += 1;
            }
        }
    }
    
    #Summary
    my $Summary = "<h2 style='margin-bottom:0px;padding-bottom:0px;'>Summary</h2><hr/>";
    $Summary .= "<table cellpadding='3' border='1' style='border-collapse:collapse;'>";
    
    
    my $Checked_Headers_Link = "0";
    $Checked_Headers_Link = "<a href='#Checked_Headers' style='color:Blue;'>".keys(%{$HeaderDestination{1}})."</a>" if(keys(%{$HeaderDestination{1}})>0);
    $Summary .= "<tr><td class='table_header summary_item'>Total headers checked</td><td align='right' style='width:40px;' class='summary_item_value'>$Checked_Headers_Link</td></tr>";
    
    my $Checked_Libs_Link = "0";
    $Checked_Libs_Link = "<a href='#Checked_Libs' style='color:Blue;'>".keys(%{$Library{1}})."</a>" if(keys(%{$Library{1}})>0);
    $Summary .= "<tr><td class='table_header summary_item'>Total libraries checked</td><td align='right' class='summary_item_value'>$Checked_Libs_Link</td></tr>";
    
    my $Verdict = "<span style='color:Green;'><b>Compatible</b></span>";
    $Verdict = "<span style='color:Red;'><b>Incompatible</b></span>" if(($Withdrawn>0) or ($I_Problems_High>0) or ($T_Problems_High>0));
    $Summary .= "<tr><td class='table_header summary_item'>Verdict</td><td align='right' width='120px;'>$Verdict</td></tr>";
    
    $Summary .= "</table>\n";
    
    #Problem Summary
    my $Problem_Summary = "<h2 style='margin-bottom:0px;padding-bottom:0px;'>Problem Summary</h2><hr/>";
    $Problem_Summary .= "<table cellpadding='3' border='1' style='border-collapse:collapse;'>";
    
    my $Added_Link = "0";
    $Added_Link = "<a href='#Added' style='color:Blue;'>$Added</a>" if($Added>0);
    $Problem_Summary .= "<tr><td class='table_header summary_item' colspan='2'>Added interfaces</td><td align='right' class='summary_item_value'>$Added_Link</td></tr>";
    
    my $WIthdrawn_Link = "0";
    $WIthdrawn_Link = "<a href='#Withdrawn' style='color:Blue;'>$Withdrawn</a>" if($Withdrawn>0);
    $Problem_Summary .= "<tr><td class='table_header summary_item' colspan='2'>Withdrawn interfaces</td><td align='right' class='summary_item_value'>$WIthdrawn_Link</td></tr>";
    
    my $TH_Link = "0";
    $TH_Link = "<a href='#Type_Problems_High' style='color:Blue;'>$T_Problems_High</a>" if($T_Problems_High>0);
    $Problem_Summary .= "<tr><td class='table_header summary_item' rowspan='3'>Problems in<br/>Data Types</td><td class='table_header summary_item' style='color:Red;'>High risk</td><td align='right' class='summary_item_value'>$TH_Link</td></tr>";
    
    my $TM_Link = "0";
    $TM_Link = "<a href='#Type_Problems_Medium' style='color:Blue;'>$T_Problems_Medium</a>" if($T_Problems_Medium>0);
    $Problem_Summary .= "<tr><td class='table_header summary_item'>Medium risk</td><td align='right' class='summary_item_value'>$TM_Link</td></tr>";
    
    my $TL_Link = "0";
    $TL_Link = "<a href='#Type_Problems_Low' style='color:Blue;'>$T_Problems_Low</a>" if($T_Problems_Low>0);
    $Problem_Summary .= "<tr><td class='table_header summary_item'>Low risk</td><td align='right' class='summary_item_value'>$TL_Link</td></tr>";
    
    my $IH_Link = "0";
    $IH_Link = "<a href='#Interface_Problems_High' style='color:Blue;'>$I_Problems_High</a>" if($I_Problems_High>0);
    $Problem_Summary .= "<tr><td class='table_header summary_item' rowspan='3'>Interface<br/>problems</td><td class='table_header summary_item' style='color:Red;'>High risk</td><td align='right' class='summary_item_value'>$IH_Link</td></tr>";
    
    my $IM_Link = "0";
    $IM_Link = "<a href='#Interface_Problems_Medium' style='color:Blue;'>$I_Problems_Medium</a>" if($I_Problems_Medium>0);
    $Problem_Summary .= "<tr><td class='table_header summary_item'>Medium risk</td><td align='right' class='summary_item_value'>$IM_Link</td></tr>";
    
    my $IL_Link = "0";
    $IL_Link = "<a href='#Interface_Problems_Low' style='color:Blue;'>$I_Problems_Low</a>" if($I_Problems_Low>0);
    $Problem_Summary .= "<tr><td class='table_header summary_item'>Low risk</td><td align='right' class='summary_item_value'>$IL_Link</td></tr>";
    
    $Problem_Summary .= "</table>\n";
    return "<!--Summary-->\n".$Summary.$Problem_Summary."<!--Summary_End-->\n";
}

sub get_Report_Added()
{
    my $ADDED_INTERFACES;
    #Added interfaces
    my %FuncAddedInHeaderLib;
    foreach my $FuncName (sort keys(%CompatProblems))
    {
        foreach my $Kind (sort keys(%{$CompatProblems{$FuncName}}))
        {
            foreach my $Location (sort keys(%{$CompatProblems{$FuncName}{$Kind}}))
            {
                if($Kind eq "Added_Interface")
                {
                    $FuncAddedInHeaderLib{$CompatProblems{$FuncName}{$Kind}{$Location}{'Header'}}{$CompatProblems{$FuncName}{$Kind}{$Location}{'New_SoName'}}{$FuncName} = 1;
                    last;
                }
            }
        }
    }
    my $Added_Number = 0;
    foreach my $HeaderName (sort keys(%FuncAddedInHeaderLib))
    {
        foreach my $SoName (sort keys(%{$FuncAddedInHeaderLib{$HeaderName}}))
        {
            if($HeaderName)
            {
                $ADDED_INTERFACES .= "<span class='header_name'>$HeaderName</span>, <span class='solib_name'>$SoName</span><br/>\n";
            }
            else
            {
                $ADDED_INTERFACES .= "<span class='solib_name'>$SoName</span><br/>\n";
            }
            foreach my $FuncName (sort {$CompatProblems{$a}{'Added_Interface'}{'SharedLibrary'}{'Signature'} <=> $CompatProblems{$b}{'Added_Interface'}{'SharedLibrary'}{'Signature'}} keys(%{$FuncAddedInHeaderLib{$HeaderName}{$SoName}}))
            {
                $Added_Number += 1;
                my $SubReport = "";
                my $Signature = $CompatProblems{$FuncName}{'Added_Interface'}{'SharedLibrary'}{'Signature'};
                if($FuncName =~ /\A_Z/)
                {
                    if($Signature)
                    {
                        $SubReport = insertIDs($ContentSpanStart.highLight_Signature_Italic(htmlSpecChars($Signature)).$ContentSpanEnd."<br/>\n".$ContentDivStart."<span class='mangled'>[ mangled name: <b>$FuncName</b> ]</span><br/><br/>".$ContentDivEnd."\n");
                    }
                    else
                    {
                        $SubReport = "<span class=\"interface_name\">".$FuncName."</span>"."<br/>\n";
                    }
                }
                else
                {
                    if($Signature)
                    {
                        $SubReport = "<span class=\"interface_name\">".highLight_Signature_Italic($Signature)."</span>"."<br/>\n";
                    }
                    else
                    {
                        $SubReport = "<span class=\"interface_name\">".$FuncName."</span>"."<br/>\n";
                    }
                }
                $ADDED_INTERFACES .= $SubReport;
            }
            $ADDED_INTERFACES .= "<br/>\n";
        }
    }
    if($ADDED_INTERFACES)
    {
        $ADDED_INTERFACES = "<a name='Added'></a><h2 style='margin-bottom:0px;padding-bottom:0px;'>Added Interfaces ($Added_Number)</h2><hr/>\n"."<!--Added_Interfaces-->\n".$ADDED_INTERFACES."<!--Added_Interfaces_End-->\n"."<input id='Added_Interfaces_Count' type='hidden' value=\'$Added_Number\' /><a style='font-size:11px;' href='#Top'>to the top</a><br/>\n";
    }
    return $ADDED_INTERFACES;
}

sub get_Report_Withdrawn()
{
    my $WITHDRAWN_INTERFACES;
    #Withdrawn interfaces
    my %FuncWithdrawnFromHeaderLib;
    foreach my $FuncName (sort keys(%CompatProblems))
    {
        foreach my $Kind (sort keys(%{$CompatProblems{$FuncName}}))
        {
            foreach my $Location (sort keys(%{$CompatProblems{$FuncName}{$Kind}}))
            {
                if($Kind eq "Withdrawn_Interface")
                {
                    $FuncWithdrawnFromHeaderLib{$CompatProblems{$FuncName}{$Kind}{$Location}{'Header'}}{$CompatProblems{$FuncName}{$Kind}{$Location}{'Old_SoName'}}{$FuncName} = 1;
                    last;
                }
            }
        }
    }
    my $Withdrawn_Number = 0;
    foreach my $HeaderName (sort keys(%FuncWithdrawnFromHeaderLib))
    {
        foreach my $SoName (sort keys(%{$FuncWithdrawnFromHeaderLib{$HeaderName}}))
        {
            if($HeaderName)
            {
                $WITHDRAWN_INTERFACES .= "<span class='header_name'>$HeaderName</span>, <span class='solib_name'>$SoName</span><br/>\n";
            }
            else
            {
                $WITHDRAWN_INTERFACES .= "<span class='solib_name'>$SoName</span><br/>\n";
            }
            foreach my $FuncName (sort keys(%{$FuncWithdrawnFromHeaderLib{$HeaderName}{$SoName}}))
            {
                $Withdrawn_Number += 1;
                my $SubReport = "";
                my $Signature = $CompatProblems{$FuncName}{'Withdrawn_Interface'}{'SharedLibrary'}{'Signature'};
                if($FuncName =~ /\A_Z/)
                {
                    if($Signature)
                    {
                        $SubReport = insertIDs($ContentSpanStart.highLight_Signature_Italic(htmlSpecChars($Signature)).$ContentSpanEnd."<br/>\n".$ContentDivStart."<span class='mangled'>[ mangled name: <b>$FuncName</b> ]</span><br/><br/>".$ContentDivEnd."\n");
                    }
                    else
                    {
                        $SubReport = "<span class=\"interface_name\">".$FuncName."</span>"."<br/>\n";
                    }
                }
                else
                {
                    if($Signature)
                    {
                        $SubReport = "<span class=\"interface_name\">".highLight_Signature_Italic($Signature)."</span>"."<br/>\n";
                    }
                    else
                    {
                        $SubReport = "<span class=\"interface_name\">".$FuncName."</span>"."<br/>\n";
                    }
                }
                $WITHDRAWN_INTERFACES .= $SubReport;
            }
            $WITHDRAWN_INTERFACES .= "<br/>\n";
        }
    }
    if($WITHDRAWN_INTERFACES)
    {
        $WITHDRAWN_INTERFACES = "<a name='Withdrawn'></a><h2 style='margin-bottom:0px;padding-bottom:0px;'>Withdrawn Interfaces ($Withdrawn_Number)</h2><hr/>\n"."<!--Withdrawn_Interfaces-->\n".$WITHDRAWN_INTERFACES."<!--Withdrawn_Interfaces_End-->\n"."<input id='Withdrawn_Interfaces_Count' type='hidden' value=\'$Withdrawn_Number\' /><a style='font-size:11px;' href='#Top'>to the top</a><br/>\n";
    }
    return $WITHDRAWN_INTERFACES;
}

sub get_Report_InterfaceProblems($)
{
    my $TargetPriority = $_[0];
    my $INTERFACE_PROBLEMS;
    my %FuncHeaderLib;
    foreach my $FuncName (sort keys(%CompatProblems))
    {
        foreach my $Kind (sort keys(%{$CompatProblems{$FuncName}}))
        {
            if($InterfaceProblems_Kind{$Kind} and ($Kind ne "Added_Interface") and ($Kind ne "Withdrawn_Interface"))
            {
                foreach my $Location (sort keys(%{$CompatProblems{$FuncName}{$Kind}}))
                {
                    $FuncHeaderLib{$CompatProblems{$FuncName}{$Kind}{$Location}{'New_SoName'}}{$CompatProblems{$FuncName}{$Kind}{$Location}{'Header'}}{$FuncName} = 1;
                    last;
                }
            }
        }
    }
    my $Problems_Number = 0;
    #Interface problems
    foreach my $SoName (sort keys(%FuncHeaderLib))
    {
        foreach my $HeaderName (sort keys(%{$FuncHeaderLib{$SoName}}))
        {
            my $HEADER_LIB_REPORT = "";
            foreach my $FuncName (sort keys(%{$FuncHeaderLib{$SoName}{$HeaderName}}))
            {
                my $Signature = "";
                my $InterfaceProblemsReport = "";
                my $ProblemNum = 1;
                foreach my $Kind (keys(%{$CompatProblems{$FuncName}}))
                {
                    foreach my $Location (keys(%{$CompatProblems{$FuncName}{$Kind}}))
                    {
                        my $Incompatibility = "";
                        my $Effect = "";
                        my $Old_Value = $CompatProblems{$FuncName}{$Kind}{$Location}{'Old_Value'};
                        my $New_Value = $CompatProblems{$FuncName}{$Kind}{$Location}{'New_Value'};
                        my $Priority = $CompatProblems{$FuncName}{$Kind}{$Location}{'Priority'};
                        my $Target = $CompatProblems{$FuncName}{$Kind}{$Location}{'Target'};
                        my $Old_Size = $CompatProblems{$FuncName}{$Kind}{$Location}{'Old_Size'};
                        my $New_Size = $CompatProblems{$FuncName}{$Kind}{$Location}{'New_Size'};
                        my $InitialType_Type = $CompatProblems{$FuncName}{$Kind}{$Location}{'InitialType_Type'};
                        my $Parameter_Position = $CompatProblems{$FuncName}{$Kind}{$Location}{'Parameter_Position'};
                        my $Parameter_Position_Str = num_to_str($Parameter_Position + 1);
                        $Signature = $CompatProblems{$FuncName}{$Kind}{$Location}{'Signature'} if(not $Signature);
                        next if($Priority ne $TargetPriority);
                        if($Kind eq "Function_Become_Static")
                        {
                            $Incompatibility = "Function become <b>static</b>\n";
                            $Effect = "Layout of parameter's stack has been changed and therefore parameters on highest positions in stack will be incorrectly initialized by application";
                        }
                        elsif($Kind eq "Function_Become_NonStatic")
                        {
                            $Incompatibility = "Function become <b>non-static</b>\n";
                            $Effect = "Layout of parameter's stack has been changed and therefore parameters on highest positions in stack will be incorrectly initialized by application";
                        }
                        elsif($Kind eq "Parameter_Type_And_Size")
                        {
                            $Incompatibility = "Type of $Parameter_Position_Str parameter <b>$Target</b> has been changed from <span style='white-space:nowrap;'><b>$Old_Value</b> (<b>$Old_Size</b> bytes)</span> to <span style='white-space:nowrap;'><b>$New_Value</b> (<b>$New_Size</b> bytes)</span>\n";
                            $Effect = "Layout of parameter's stack has been changed and therefore parameters on highest positions in stack will be incorrectly initialized by application";
                        }
                        elsif($Kind eq "Parameter_Type")
                        {
                            $Incompatibility = "Type of $Parameter_Position_Str parameter <b>$Target</b> has been changed from <span style='white-space:nowrap;'><b>$Old_Value</b></span> to <span style='white-space:nowrap;'><b>$New_Value</b></span>\n";
                            $Effect = "Replacement of parameter data type may be caused by changes in semantic meaning of this parameter";
                        }
                        elsif($Kind eq "Parameter_BaseType")
                        {
                            if($InitialType_Type eq "Pointer")
                            {
                                $Incompatibility = "Base type of $Parameter_Position_Str parameter <b>$Target</b> (pointer) has been changed from <span style='white-space:nowrap;'><b>$Old_Value</b> (<b>$Old_Size</b> bytes)</span> to <span style='white-space:nowrap;'><b>$New_Value</b> (<b>$New_Size</b> bytes)</span>\n";
                                $Effect = "Memory stored by pointer will be incorrectly initialized by application";
                            }
                            else
                            {
                                $Incompatibility = "Base type of $Parameter_Position_Str parameter <b>$Target</b> has been changed from <span style='white-space:nowrap;'><b>$Old_Value</b> (<b>$Old_Size</b> bytes)</span> to <span style='white-space:nowrap;'><b>$New_Value</b> (<b>$New_Size</b> bytes)</span>\n";
                                $Effect = "Layout of parameter's stack has been changed and therefore parameters on highest positions in stack will be incorrectly initialized by application";
                            }
                        }
                        elsif($Kind eq "Parameter_PointerLevel_And_Size")
                        {
                            $Incompatibility = "Type pointer level of $Parameter_Position_Str parameter <b>$Target</b> has been changed from <b>$Old_Value</b> to <b>$New_Value</b> and size of type has been changed from <b>$Old_Size</b> bytes to <b>$New_Size</b> bytes\n";
                            $Effect = "Layout of parameter's stack has been changed and therefore parameters on highest positions in stack will be incorrectly initialized by application";
                        }
                        elsif($Kind eq "Parameter_PointerLevel")
                        {
                            $Incompatibility = "Type pointer level of $Parameter_Position_Str parameter <b>$Target</b> has been changed from <b>$Old_Value</b> to <b>$New_Value</b>\n";
                            $Effect = "Incorrect initialization of $Parameter_Position_Str parameter <b>$Target</b> by application";
                        }
                        elsif($Kind eq "Return_Type_And_Size")
                        {
                            $Incompatibility = "Type of return value has been changed from <span style='white-space:nowrap;'><b>$Old_Value</b> (<b>$Old_Size</b> bytes)</span> to <span style='white-space:nowrap;'><b>$New_Value</b> (<b>$New_Size</b> bytes)</span>\n";
                            $Effect = "Applications will have got different return value and it's execution may change";
                        }
                        elsif($Kind eq "Return_Type")
                        {
                            $Incompatibility = "Type of return value has been changed from <span style='white-space:nowrap;'><b>$Old_Value</b></span> to <span style='white-space:nowrap;'><b>$New_Value</b></span>\n";
                            $Effect = "Applications will have got different return value and it's execution may change";
                        }
                        elsif($Kind eq "Return_BaseType")
                        {
                            $Incompatibility = "Base type of return value has been changed from <span style='white-space:nowrap;'><b>$Old_Value</b> (<b>$Old_Size</b> bytes)</span> to <span style='white-space:nowrap;'><b>$New_Value</b> (<b>$New_Size</b> bytes)</span>\n";
                            $Effect = "Applications will have got different return value and it's execution may change";
                        }
                        elsif($Kind eq "Return_PointerLevel_And_Size")
                        {
                            $Incompatibility = "Type pointer level of return value has been changed from <b>$Old_Value</b> to <b>$New_Value</b> and size of type has been changed from <b>$Old_Size</b> bytes to <b>$New_Size</b> bytes\n";
                            $Effect = "Applications will have got different return value and it's execution may change";
                        }
                        elsif($Kind eq "Return_PointerLevel")
                        {
                            $Incompatibility = "Type pointer level of return value has been changed from <b>$Old_Value</b> to <b>$New_Value</b>\n";
                            $Effect = "Applications will have got different return value and it's execution may change";
                        }
                        if($Incompatibility)
                        {
                            $InterfaceProblemsReport .= "<tr><td align='center' class='table_header'><span class='problem_num'>$ProblemNum</span></td><td align='left' valign='top'><span class='problem_body'>".$Incompatibility."</span></td><td align='left' valign='top'><span class='problem_body'>".$Effect."</span></td></tr>\n";
                            $ProblemNum += 1;
                            $Problems_Number += 1;
                        }
                    }
                }
                $ProblemNum -= 1;
                if($InterfaceProblemsReport)
                {
                    if($FuncName =~ /\A_Z/)
                    {
                        if($Signature)
                        {
                            $HEADER_LIB_REPORT .= $ContentSpanStart."[+] ".highLight_Signature_Italic(htmlSpecChars($Signature))." ($ProblemNum)".$ContentSpanEnd."<br/>\n$ContentDivStart<span class='mangled'>[ mangled name: <b>$FuncName</b> ]</span><br/>\n";
                        }
                        else
                        {
                            $HEADER_LIB_REPORT .= $ContentSpanStart."[+] ".$FuncName." ($ProblemNum)".$ContentSpanEnd."<br/>\n$ContentDivStart\n";
                        }
                    }
                    else
                    {
                        if($Signature)
                        {
                            $HEADER_LIB_REPORT .= $ContentSpanStart."[+] ".highLight_Signature_Italic(htmlSpecChars($Signature))." ($ProblemNum)".$ContentSpanEnd."<br/>\n$ContentDivStart\n";
                        }
                        else
                        {
                            $HEADER_LIB_REPORT .= $ContentSpanStart."[+] ".$FuncName." ($ProblemNum)".$ContentSpanEnd."<br/>\n$ContentDivStart\n";
                        }
                    }
                    $HEADER_LIB_REPORT .= "<table width='900px' cellpadding='3' cellspacing='0' class='problems_table'><tr><td align='center' width='2%' class='table_header'><span class='problem_title' style='white-space:nowrap;'></span></td><td width='47%' align='center' class='table_header'><span class='problem_sub_title'>Incompatibility</span></td><td align='center' class='table_header'><span class='problem_sub_title'>Effect</span></td></tr>$InterfaceProblemsReport</table><br/>$ContentDivEnd\n";
                    $HEADER_LIB_REPORT = insertIDs($HEADER_LIB_REPORT);
                }
            }
            if($HEADER_LIB_REPORT)
            {
                $INTERFACE_PROBLEMS .= "<span class='header_name'>$HeaderName</span>, <span class='solib_name'>$SoName</span><br/>\n".$HEADER_LIB_REPORT."<br/>";
            }
        }
    }
    if($INTERFACE_PROBLEMS)
    {
        $INTERFACE_PROBLEMS = "<a name=\'Interface_Problems_$TargetPriority\'></a>\n<h2 style='margin-bottom:0px;padding-bottom:0px;'>Interface problems, $TargetPriority risk ($Problems_Number)</h2><hr/>\n"."<!--Interface_Problems_".$TargetPriority."-->\n".$INTERFACE_PROBLEMS."<!--Interface_Problems_".$TargetPriority."_End-->\n"."<input id=\'Interface_Problems_$TargetPriority"."_Count"."\' type='hidden' value=\'$Problems_Number\' /><a style='font-size:11px;' href='#Top'>to the top</a><br/>\n";
    }
    return $INTERFACE_PROBLEMS;
}

sub get_Report_TypeProblems($)
{
    my $TargetPriority = $_[0];
    my $TYPE_PROBLEMS;
    my %TypeHeader;
    my %TypeChanges;
    foreach my $FuncName (sort keys(%CompatProblems))
    {
        foreach my $Kind (keys(%{$CompatProblems{$FuncName}}))
        {
            if($TypeProblems_Kind{$Kind})
            {
                foreach my $Location (keys(%{$CompatProblems{$FuncName}{$Kind}}))
                {
                    my $Type_Name = $CompatProblems{$FuncName}{$Kind}{$Location}{'Type_Name'};
                    my $Priority = $CompatProblems{$FuncName}{$Kind}{$Location}{'Priority'};
                    my $Type_Header = $CompatProblems{$FuncName}{$Kind}{$Location}{'Header'};
                    %{$TypeChanges{$Type_Name}{$Kind}{$Location}} = %{$CompatProblems{$FuncName}{$Kind}{$Location}};
                    $TypeHeader{$Type_Header}{$Type_Name} = 1;
                    $TypeChanges{$Type_Name}{$Kind}{$Location}{'Priority'} = max_priority($TypeChanges{$Type_Name}{$Kind}{$Location}{'Priority'}, $Priority);
                }
            }
        }
    }
    my $Problems_Number = 0;
    foreach my $HeaderName (sort keys(%TypeHeader))
    {
        my $HEADER_REPORT = "";
        foreach my $TypeName (sort keys(%{$TypeHeader{$HeaderName}}))
        {
            my $ProblemNum = 1;
            my $TypeProblemsReport = "";
            my %Kinds_Locations = ();
            my %Kinds_Target = ();
            foreach my $Kind (keys(%{$TypeChanges{$TypeName}}))
            {
                foreach my $Location (keys(%{$TypeChanges{$TypeName}{$Kind}}))
                {
                    my $Priority = $TypeChanges{$TypeName}{$Kind}{$Location}{'Priority'};
                    next if($Priority ne $TargetPriority);
                    $Kinds_Locations{$Kind}{$Location} = 1;
                    my $Incompatibility = "";
                    my $Effect = "";
                    my $Target = $TypeChanges{$TypeName}{$Kind}{$Location}{'Target'};
                    next if($Kinds_Target{$Kind}{$Target});
                    $Kinds_Target{$Kind}{$Target} = 1;
                    my $Old_Value = $TypeChanges{$TypeName}{$Kind}{$Location}{'Old_Value'};
                    my $New_Value = $TypeChanges{$TypeName}{$Kind}{$Location}{'New_Value'};
                    my $Old_Size = $TypeChanges{$TypeName}{$Kind}{$Location}{'Old_Size'};
                    my $New_Size = $TypeChanges{$TypeName}{$Kind}{$Location}{'New_Size'};
                    my $Type_Type = $TypeChanges{$TypeName}{$Kind}{$Location}{'Type_Type'};
                    my $InitialType_Type = $TypeChanges{$TypeName}{$Kind}{$Location}{'InitialType_Type'};
                    
                    if($Kind eq "Added_Virtual_Function")
                    {
                        $Incompatibility = "Virtual method "."<span class='interface_name_black'>".highLight_Signature($Target)."</span>"." has been added to this class and therefore the layout of virtual table has been changed";
                        $Effect = "Call of any virtual method in this class and it's subclasses will result in crash of application";
                    }
                    elsif($Kind eq "Withdrawn_Virtual_Function")
                    {
                        $Incompatibility = "Virtual method "."<span class='interface_name_black'>".highLight_Signature($Target)."</span>"." has been withdrawn from this class and therefore the layout of virtual table has been changed";
                        $Effect = "Call of any virtual method in this class and it's subclasses will result in crash of application";
                    }
                    elsif($Kind eq "Virtual_Function_Position")
                    {
                        $Incompatibility = "The relative position of virtual method "."<span class='interface_name_black'>".highLight_Signature($Target)."</span>"." has been changed from <b>$Old_Value</b> to <b>$New_Value</b> and therefore the layout of virtual table has been changed";
                        $Effect = "Call of this virtual method will result in crash of application";
                    }
                    elsif($Kind eq "Virtual_Function_Redefinition")
                    {
                        $Incompatibility = "Virtual method "."<span class='interface_name_black'>".highLight_Signature($Old_Value)."</span>"." has been redefined by "."<span class='interface_name_black'>".highLight_Signature($New_Value)."</span>";
                        $Effect = "Method <span class='interface_name_black'>".highLight_Signature($New_Value)."</span> will be called instead of <span class='interface_name_black'>".highLight_Signature($Old_Value)."</span>";
                    }
                    elsif($Kind eq "Virtual_Function_Redefinition_B")
                    {
                        $Incompatibility = "Virtual method "."<span class='interface_name_black'>".highLight_Signature($New_Value)."</span>"." has been redefined by "."<span class='interface_name_black'>".highLight_Signature($Old_Value)."</span>";
                        $Effect = "Method <span class='interface_name_black'>".highLight_Signature($Old_Value)."</span> will be called instead of <span class='interface_name_black'>".highLight_Signature($New_Value)."</span>";
                    }
                    elsif($Kind eq "Size")
                    {
                        $Incompatibility = "Size of this type has been changed from <b>$Old_Value</b> to <b>$New_Value</b> bytes";
                        $Effect = "Change of type size may lead to different effects in different contexts. $ContentSpanStart"."<span style='color:Black'>[+] ...</span>"."$ContentSpanEnd $ContentDivStart In context of some function parameter this change affects on parameter's stack layout and lead to incorrect initialization of parameters on highest positions in stack. In context of some structure member this change affects on members layout and lead to incorrect access of application to members on highest positions. Other affects are possible$ContentDivEnd";
                    }
                    elsif($Kind eq "Added_Member")
                    {
                        $Incompatibility = "Member <b>$Target</b> has been added to this type";
                        $Effect = "Size of inclusive type has been changed";
                    }
                    elsif($Kind eq "Added_Middle_Member")
                    {
                        $Incompatibility = "Member <b>$Target</b> has been added between the first member and the last member of this structural type.";
                        $Effect = "Layout of structure members has been changed and therefore members on highest positions in structure definition will be incorrectly accessed by application";
                    }
                    elsif($Kind eq "Member_Rename")
                    {
                        $Incompatibility = "Member <b>$Target</b> has been renamed to <b>$New_Value</b>.";
                        $Effect = "Renaming of member in structural data type may be caused by changes in semantic meaning of this member";
                    }
                    elsif($Kind eq "Withdrawn_Member_And_Size")
                    {
                        $Incompatibility = "Member <b>$Target</b> has been withdrawn from this type";
                        $Effect = "Applications will access to incorrect memory while accessing to this member. Also it affects on size of inclusive type";
                    }
                    elsif($Kind eq "Withdrawn_Member")
                    {
                        $Incompatibility = "Member <b>$Target</b> has been withdrawn from this type";
                        $Effect = "Applications will access to incorrect memory while accessing to this member";
                    }
                    elsif($Kind eq "Withdrawn_Middle_Member_And_Size")
                    {
                        $Incompatibility = "Member <b>$Target</b> has been withdrawn from this structural type between the first member and the last member";
                        $Effect = "Layout of structure members has been changed and therefore members on highest positions in structure definition will be incorrectly accessed by application. Also previous access of application to withdrawn member will be incorrect";
                    }
                    elsif($Kind eq "Withdrawn_Middle_Member")
                    {
                        $Incompatibility = "Member <b>$Target</b> has been withdrawn from this structural type between the first member and the last member";
                        $Effect = "Applications will access to incorrect memory while accessing to this member.";
                    }
                    elsif($Kind eq "Enum_Member_Value")
                    {
                        $Incompatibility = "Value of member <b>$Target</b> has been changed from <b>$Old_Value</b> to <b>$New_Value</b>";
                        $Effect = "Application will execute another branch of library code";
                    }
                    elsif($Kind eq "Enum_Member_Name")
                    {
                        $Incompatibility = "Name of member with value <b>$Target</b> has been changed from <b>$Old_Value</b> to <b>$New_Value</b>";
                        $Effect = "Application may execute another branch of library code";
                    }
                    elsif($Kind eq "Member_Type_And_Size")
                    {
                        $Incompatibility = "Type of member <b>$Target</b> has been changed from <span style='white-space:nowrap;'><b>$Old_Value</b> (<b>$Old_Size</b> bytes)</span> to <span style='white-space:nowrap;'><b>$New_Value</b> (<b>$New_Size</b> bytes)</span>";
                        $Effect = "Layout of structure members has been changed and therefore members on highest positions in structure definition will be incorrectly accessed by application";
                    }
                    elsif($Kind eq "Member_Type")
                    {
                        $Incompatibility = "Type of member <b>$Target</b> has been changed from <span style='white-space:nowrap;'><b>$Old_Value</b></span> to <span style='white-space:nowrap;'><b>$New_Value</b></span>";
                        $Effect = "Replacement of member data type may be caused by changes in semantic meaning of this member";
                    }
                    elsif($Kind eq "Member_BaseType")
                    {
                        if($InitialType_Type eq "Pointer")
                        {
                            $Incompatibility = "Base type of member <b>$Target</b> (pointer) has been changed from <span style='white-space:nowrap;'><b>$Old_Value</b> (<b>$Old_Size</b> bytes)</span> to <span style='white-space:nowrap;'><b>$New_Value</b> (<b>$New_Size</b> bytes)</span>";
                            $Effect = "Possible access of application to incorrect memory by member pointer";
                        }
                        else
                        {
                            $Incompatibility = "Base type of member <b>$Target</b> has been changed from <span style='white-space:nowrap;'><b>$Old_Value</b> (<b>$Old_Size</b> bytes)</span> to <span style='white-space:nowrap;'><b>$New_Value</b> (<b>$New_Size</b> bytes)</span>";
                            $Effect = "Layout of structure members has been changed and therefore members on highest positions in structure definition will be incorrectly accessed by application";
                        }
                    }
                    elsif($Kind eq "Member_PointerLevel_And_Size")
                    {
                        $Incompatibility = "Type pointer level of member <b>$Target</b> has been changed from <b>$Old_Value</b> to <b>$New_Value</b> and size of type has been changed from <b>$Old_Size</b> bytes to <b>$New_Size</b> bytes";
                        $Effect = "Layout of structure members has been changed and therefore members on highest positions in stack will be incorrectly initialized by application";
                    }
                    elsif($Kind eq "Member_PointerLevel")
                    {
                        $Incompatibility = "Type pointer level of member <b>$Target</b> has been changed from <b>$Old_Value</b> to <b>$New_Value</b>";
                        $Effect = "Incorrect initialization of member <b>$Target</b> by application";
                    }
                    if($Incompatibility)
                    {
                        $TypeProblemsReport .= "<tr><td align='center' valign='top' class='table_header'><span class='problem_num'>$ProblemNum</span></td><td align='left' valign='top'><span class='problem_body'>".$Incompatibility."</span></td><td class='problem_body'>$Effect</td></tr>\n";
                        $ProblemNum += 1;
                        $Problems_Number += 1;
                        $Kinds_Locations{$Kind}{$Location} = 1;
                    }
                }
            }
            $ProblemNum -= 1;
            if($TypeProblemsReport)
            {
                my ($Affected_Interfaces_Header, $Affected_Interfaces) = getAffectedInterfaces($TypeName, \%Kinds_Locations);
                $HEADER_REPORT .= $ContentSpanStart."[+] ".$TypeName." ($ProblemNum)".$ContentSpanEnd."<br/>\n$ContentDivStart<table width='900px' cellpadding='3' cellspacing='0' class='problems_table'><tr><td align='center' width='2%' class='table_header'><span class='problem_title' style='white-space:nowrap;'></span></td><td width='47%' align='center' class='table_header'><span class='problem_sub_title'>Incompatibility</span></td><td align='center' class='table_header'><span class='problem_sub_title'>Effect</span></td></tr>$TypeProblemsReport</table>"."<span style='padding-left:10px'>$Affected_Interfaces_Header</span>$Affected_Interfaces<br/><br/>$ContentDivEnd\n";
                $HEADER_REPORT = insertIDs($HEADER_REPORT);
            }
        }
        if($HEADER_REPORT)
        {
            $TYPE_PROBLEMS .= "<span class='header_name'>$HeaderName</span><br/>\n".$HEADER_REPORT."<br/>";
        }
    }
    if($TYPE_PROBLEMS)
    {
        my $Notations = "Shorthand notations:<span style='color:#444444;padding-left:5px;'><b>RetVal</b></span> - function's return value, <span style='color:#444444;'><b>Obj</b></span> - method's object (C++).<br/>\n";
        $Notations = "" if($TYPE_PROBLEMS !~ /'RetVal|'Obj/);
        $TYPE_PROBLEMS = "<a name=\'Type_Problems_$TargetPriority\'></a>\n<h2 style='margin-bottom:0px;padding-bottom:0px;'>Problems in Data Types, $TargetPriority risk ($Problems_Number)</h2><hr/>\n".$Notations."<!--Type_Problems_".$TargetPriority."-->\n".$TYPE_PROBLEMS."<!--Type_Problems_".$TargetPriority."_End-->\n"."<input id=\'Type_Problems_$TargetPriority"."_Count"."\' type='hidden' value=\'$Problems_Number\' /><a style='font-size:11px;' href='#Top'>to the top</a><br/>\n";
    }
    return $TYPE_PROBLEMS;
}

my $ContentSpanStart_2 = "<span style='line-height:25px;' class=\"section_2\" onclick=\"javascript:showContent(this, 'CONTENT_ID')\">\n";

sub getAffectedInterfaces($$)
{
    my $Target_TypeName = $_[0];
    my $Kinds_Locations = $_[1];
    my $Affected_Interfaces_Header = "";
    my $Affected_Interfaces = "";
    my %FunctionNumber;
    foreach my $FuncName (sort keys(%CompatProblems))
    {
        next if(($FuncName =~ /C2/) or ($FuncName =~ /D2/));
        next if(keys(%FunctionNumber)>5000);
        my $FunctionProblem = "";
        my $MinPath_Length = "";
        my $MaxPriority = 0;
        my $Location_Last = "";
        foreach my $Kind (keys(%{$CompatProblems{$FuncName}}))
        {
            foreach my $Location (keys(%{$CompatProblems{$FuncName}{$Kind}}))
            {
                next if(not $Kinds_Locations->{$Kind}{$Location});
                my $Type_Name = $CompatProblems{$FuncName}{$Kind}{$Location}{'Type_Name'};
                my $Signature = $CompatProblems{$FuncName}{$Kind}{$Location}{'Signature'};
                my $Parameter_Position = $CompatProblems{$FuncName}{$Kind}{$Location}{'Parameter_Position'};
                my $Priority = $CompatProblems{$FuncName}{$Kind}{$Location}{'Priority'};
                if($Type_Name eq $Target_TypeName)
                {
                    $FunctionNumber{$FuncName} = 1;
                    my $Path_Length = 0;
                    while($Location =~ /\-\>/g){$Path_Length += 1;}
                    if(($MinPath_Length eq "") or ($Path_Length<$MinPath_Length and $Priority_Value{$Priority}>$MaxPriority) or (($Location_Last =~ /RetVal/ or $Location_Last =~ /Obj/) and $Location !~ /RetVal|Obj/ and $Location !~ /\-\>/) or ($Location_Last =~ /RetVal|Obj/ and $Location_Last =~ /\-\>/ and $Location !~ /RetVal|Obj/ and $Location =~ /\-\>/))
                    {
                        $MinPath_Length = $Path_Length;
                        $MaxPriority = $Priority_Value{$Priority};
                        $Location_Last = $Location;
                        my $Description = get_AffectDescription($FuncName, $Kind, $Location);
                        $FunctionProblem = "<span class='interface_name_black' style='padding-left:20px;'>".highLight_Signature_PPos_Italic($Signature, $Parameter_Position, 1)."</span>:<br/>"."<span style='padding-left:30px;font-size:13px;font-style:italic;line-height:13px;'>".addArrows($Description)."</span><br/><div style='height:4px;'>&nbsp;</div>\n";
                    }
                }
            }
        }
        $Affected_Interfaces .= $FunctionProblem;
    }
    $Affected_Interfaces .= "and other...<br/>" if(keys(%FunctionNumber)>5000);
    if($Affected_Interfaces)
    {
        $Affected_Interfaces_Header = $ContentSpanStart_2."[+] affected interfaces (".keys(%FunctionNumber).")".$ContentSpanEnd;
        $Affected_Interfaces =  $ContentDivStart.$Affected_Interfaces.$ContentDivEnd;
    }
    return ($Affected_Interfaces_Header, $Affected_Interfaces);
}

my %Kind_TypeStructureChanged=(
    "Size"=>1,
    "Added_Member"=>1,
    "Added_Middle_Member"=>1,
    "Member_Rename"=>1,
    "Withdrawn_Member_And_Size"=>1,
    "Withdrawn_Member"=>1,
    "Withdrawn_Middle_Member_And_Size"=>1,
    "Enum_Member_Value"=>1,
    "Enum_Member_Name"=>1,
    "Member_Type_And_Size"=>1,
    "Member_Type"=>1,
    "Member_BaseType"=>1,
    "Member_PointerLevel"=>1,
    "Member_PointerLevel_And_Size"=>1
);

my %Kind_VirtualTableChanged=(
    "Added_Virtual_Function"=>1,
    "Withdrawn_Virtual_Function"=>1,
    "Virtual_Function_Position"=>1,
    "Virtual_Function_Redefinition"=>1,
    "Virtual_Function_Redefinition_B"=>1
);

sub get_AffectDescription($$$)
{
    my $FuncName = $_[0];
    my $Kind = $_[1];
    my $Location = $_[2];
    my $Target = $CompatProblems{$FuncName}{$Kind}{$Location}{'Target'};
    my $Old_Value = $CompatProblems{$FuncName}{$Kind}{$Location}{'Old_Value'};
    my $New_Value = $CompatProblems{$FuncName}{$Kind}{$Location}{'New_Value'};
    my $Type_Name = $CompatProblems{$FuncName}{$Kind}{$Location}{'Type_Name'};
    my $Parameter_Position = $CompatProblems{$FuncName}{$Kind}{$Location}{'Parameter_Position'};
    my $Parameter_Name = $CompatProblems{$FuncName}{$Kind}{$Location}{'Parameter_Name'};
    my $Parameter_Type_Name = $CompatProblems{$FuncName}{$Kind}{$Location}{'Parameter_Type_Name'};
    my $Member_Type_Name = $CompatProblems{$FuncName}{$Kind}{$Location}{'Member_Type_Name'};
    my $Object_Type_Name = $CompatProblems{$FuncName}{$Kind}{$Location}{'Object_Type_Name'};
    my $Return_Type_Name = $CompatProblems{$FuncName}{$Kind}{$Location}{'Return_Type_Name'};
    my $Start_Type_Name = $CompatProblems{$FuncName}{$Kind}{$Location}{'Start_Type_Name'};
    my $InitialType_Type = $CompatProblems{$FuncName}{$Kind}{$Location}{'InitialType_Type'};
    my $Parameter_Position_Str = num_to_str($Parameter_Position + 1);
    my @Sentence_Parts = ();
    my $Location_To_Type = $Location;
    $Location_To_Type =~ s/\-\>.+?\Z//o;
    if($Kind_VirtualTableChanged{$Kind})
    {
        if($Kind eq "Virtual_Function_Redefinition")
        {
            @Sentence_Parts = (@Sentence_Parts, "This method become virtual and will be called instead of redefined method '".highLight_Signature($Old_Value)."'.");
        }
        elsif($Kind eq "Virtual_Function_Redefinition_B")
        {
            @Sentence_Parts = (@Sentence_Parts, "This method become non-virtual and redefined method '".highLight_Signature($Old_Value)."' will be called instead of it.");
        }
        else
        {
            @Sentence_Parts = (@Sentence_Parts, "Call of this virtual method will result in crash of application because the layout of virtual table has been changed.");
        }
    }
    elsif($Kind_TypeStructureChanged{$Kind})
    {
        if($Location_To_Type =~ /RetVal/)
        {#Return value
            if($Location_To_Type =~ /\-\>/)
            {
                @Sentence_Parts = (@Sentence_Parts, "Member \'$Location_To_Type\' in return value");
            }
            else
            {
                @Sentence_Parts = (@Sentence_Parts, "Return value");
            }
        }
        elsif($Location_To_Type =~ /Obj/)
        {#Object
            if($Location_To_Type =~ /\-\>/)
            {
                @Sentence_Parts = (@Sentence_Parts, "Member \'$Location_To_Type\' in object of this function");
            }
            else
            {
                @Sentence_Parts = (@Sentence_Parts, "Object");
            }
        }
        else
        {#Parameters
            if($Location_To_Type =~ /\-\>/)
            {
                @Sentence_Parts = (@Sentence_Parts, "Member \'$Location_To_Type\' of $Parameter_Position_Str parameter");
            }
            else
            {
                @Sentence_Parts = (@Sentence_Parts, "$Parameter_Position_Str parameter");
            }
            if($Parameter_Name)
            {
                @Sentence_Parts = (@Sentence_Parts, "\'$Parameter_Name\'");
            }
            if($InitialType_Type eq "Pointer")
            {
                @Sentence_Parts = (@Sentence_Parts, "(pointer)");
            }
        }
        if($Start_Type_Name eq $Type_Name)
        {
            @Sentence_Parts = (@Sentence_Parts, "has type \'$Type_Name\'.");
        }
        else
        {
            @Sentence_Parts = (@Sentence_Parts, "has base type \'$Type_Name\'.");
        }
    }
    return join(" ", @Sentence_Parts);
}

sub create_HtmlReport()
{
    my $CssStyles = "<style type=\"text/css\">
    hr{color:Black;background-color:Black;height:1px;border: 0;}
    span.section{font-weight:bold;cursor:pointer;margin-left: 7px;font-size:16px;font-family:Arial;color:#003E69;}
    span.section_2{cursor:pointer;margin-left: 7px;font-size:14px;font-family:Arial;color:#cc3300;} span:hover.section{color:#336699;}
    span.problem_exact_location{color:Red;font-size:14px;}
    span.header_name{color:#cc3300;font-size:13px;font-family:Verdana;font-weight:bold;}
    span.solib_name{color:Green;font-size:13px;font-family:Verdana;font-weight:bold;}
    span.interface_name{font-weight:bold;font-size:16px;font-family:Arial;color:#003E69;margin-left: 7px;}
    span.interface_name_black{font-weight:bold;font-size:15px;font-family:Arial;color:#333333;}
    span.problem_title{color:#333333;font-weight:bold;font-size:13px;font-family:Verdana;}
    span.problem_sub_title{color:#333333;text-decoration:none;font-weight:bold;font-size:13px;font-family:Verdana;}
    span.problem_body{color:Black;font-size:14px;}
    span.interface_signature{font-weight:normal;}
    table.problems_table{line-height:16px;margin-left:15px;margin-top:3px;border-collapse:collapse;}
    table.problems_table td{border-style:solid;border-color:Gray;border-width:1px;}
    td.table_header{background-color:#eeeeee;}
    td.summary_item{font-size:15px;font-family:Arial;}
    td.summary_item_value{padding-right:5px;width:50px;}
    span.problem_num{color:#333333;font-weight:bold;font-size:13px;font-family:Verdana;}
    span.mangled{padding-left:15px;font-size:13px;cursor:text;color:#444444;}</style>";
    
    my $JScripts = "<script type=\"text/javascript\" language=\"JavaScript\">
    function showContent(header, id)   {
        e = document.getElementById(id);
        if(e.style.display == 'none')
        {
            e.style.display = '';
            e.style.visibility = 'visible';
            header.innerHTML = header.innerHTML.replace(/\\\[[^0-9 ]\\\]/gi,\"[&minus;]\");
        }
        else
        {
            e.style.display = 'none';
            e.style.visibility = 'hidden';
            header.innerHTML = header.innerHTML.replace(/\\\[[^0-9 ]\\\]/gi,\"[+]\");
        }
    }</script>";
    
    open(COMPAT_REPORT, ">$REPORT_PATH/abi_compat_report.html");
    print COMPAT_REPORT "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">\n<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\" lang=\"en\">\n<head>\n<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" />
    <title>ABI compliance report for library $TargetLibraryName update from $Descriptor{1}{'Version'} to $Descriptor{2}{'Version'} version on ".getArch()."\n</title>\n<!--Styles-->\n".$CssStyles."\n<!--Styles_End-->\n"."<!--JScripts-->\n".$JScripts."\n<!--JScripts_End-->\n</head>\n<body>\n<div><a name='Top'></a>\n".get_Report_Header()."<br/>\n".get_Summary()."<br/>\n".get_Report_Added().get_Report_Withdrawn().get_Report_TypeProblems("High").get_Report_TypeProblems("Medium").get_Report_TypeProblems("Low").get_Report_InterfaceProblems("High").get_Report_InterfaceProblems("Medium").get_Report_InterfaceProblems("Low").get_SourceInfo()."</div>\n"."<br/><br/><br/><hr/><div style='width:100%;font-family:Arial;font-size:11px;' align='right'><i>Generated on ".(localtime time)." for $TargetLibraryName by <a href='http://ispras.linux-foundation.org/index.php/ABI_compliance_checker'>ABI-compliance-checker</a> 1.1 &nbsp;</i></div>\n<div style='height:999px;'></div>\n</body></html>";
    close(COMPAT_REPORT);
}

sub trivialCmp($$)
{
    if(int($_[0]) > int($_[1]))
    {
        return 1;
    }
    elsif($_[0] eq $_[1])
    {
        return 0;
    }
    else
    {
        return -1;
    }
}

sub highlightLast($)
{
    my $Text = $_[0];
    if($Text =~ /.*\'[^\']+\'/)
    {
        $Text =~ s/(.*)'([^']+)'/$1'<span class='problem_exact_location'>$2<\/span>'/o;
    }
    return $Text;
}

sub addArrows($)
{
    my $Text = $_[0];
    #$Text =~ s/\-\>/&#8594;/g;
    $Text =~ s/\-\>/&minus;&gt;/g;
    return $Text;
}

my $Content_Counter = 0;
sub insertIDs($)
{
    my $Text = $_[0];
    
    while($Text =~ /CONTENT_ID/)
    {
        if(int($Content_Counter)%2)
        {
            $ContentID -= 1;
        }
        $Text =~ s/CONTENT_ID/c_$ContentID/o;
        $ContentID += 1;
        $Content_Counter += 1;
    }
    return $Text;
}

sub restrict_num_decimal_digits
{
  my $num=shift;
  my $digs_to_cut=shift;

  if ($num=~/\d+\.(\d){$digs_to_cut,}/)
  {
    $num=sprintf("%.".($digs_to_cut-1)."f", $num);
  }
  return $num;
}

sub parseHeaders_Separately()
{
    `mkdir -p header_compile_errors/$TargetLibraryName/`;
    `rm -fr header_compile_errors/$TargetLibraryName/$Descriptor{1}{'Version'}`;
    `rm -fr header_compile_errors/$TargetLibraryName/$Descriptor{2}{'Version'}`;
    my $Num = 0;
	foreach my $Header (sort keys(%{$HeaderDestination{1}}))
	{
        system("echo -e -n '\rchecked headers: $Num/".keys(%{$HeaderDestination{1}})." (".restrict_num_decimal_digits($Num*100/keys(%{$HeaderDestination{1}}), 3)."%) \'");
        $ProcessedHeader = $Header;
 		%TypeDescr = ();
 		%FuncDescr = ();
 		%ClassFunc = ();
        %ClassVirtFunc = ();
 		%LibInfo = ();
        %Functions = ();
        %Cache = ();
        $Version = 1;
		parseHeader($HeaderDestination{1}{$Header});
        $Version = 2;
        my $PairHeaderDest = $HeaderDestination{2}{$Header};
        if(not $PairHeaderDest)
        {
            $Num += 1;
            next;
        }
        parseHeader($PairHeaderDest);
        mergeHeaders();
        $Num += 1;
        system("echo -e -n '\rchecked headers: $Num/".keys(%{$HeaderDestination{1}})." (".restrict_num_decimal_digits($Num*100/keys(%{$HeaderDestination{1}}), 3)."%) \'");
	}
}

sub getHeaderStandaloneName($)
{
    my $Destination = $_[0];
    if($Destination =~ /\A(.*\/)([^\/]*)\Z/)
    {
        return $2;
    }
    else
    {
        return $Destination;
    }
}

sub getSymbols($)
{
    my $LibVersion = $_[0];
    my @SoLibPaths = getSoPaths($LibVersion);
    if($#SoLibPaths eq -1)
    {
        print "ERROR: there are no any shared objects in specified paths in library descriptor d$LibVersion\n";
        exit(1);
    }
    foreach my $SoLibPath (@SoLibPaths)
    {
        getSymbols_Lib($LibVersion, $SoLibPath);
    }
}

sub separatePath($)
{
    return ("", $_[0])if($_[0] !~ /\//);
    $_[0] =~ /\A(.*\/)([^\/]*)\Z/;
    return ($1, $2);
}

sub translateSymbols($)
{
    my $LibVersion = $_[0];
    my @MnglNames = ();
    my @UnMnglNames = ();
    foreach my $FuncName (sort keys(%{$LibInt{$LibVersion}}))
    {
        if($FuncName =~ /\A_Z/)
        {
            push(@MnglNames, $FuncName);
        }
    }
    if($#MnglNames > -1)
    {
        @UnMnglNames = reverse(unmangleArray(@MnglNames));
        foreach my $FuncName (sort keys(%{$LibInt{$LibVersion}}))
        {
            if($FuncName =~ /\A_Z/)
            {
                $tr_name{$FuncName} = pop(@UnMnglNames);
                $mangled_name{$tr_name{$FuncName}} = $FuncName;
            }
        }
    }
}

sub detectAdded()
{
    #Detecting Added
    foreach my $Int_Name (keys(%{$LibInt{2}}))
    {
        if(not $LibInt{1}{$Int_Name})
        {
            $AddedInt{$Int_Name} = 1;
        }
    }
    #Unmangling Added
    my @MnglNames = ();
    my @UnMnglNames = ();
    foreach my $FuncName (sort keys(%AddedInt))
    {
        if($FuncName =~ /\A_Z/)
        {
            push(@MnglNames, $FuncName);
        }
    }
    if($#MnglNames > -1)
    {
        @UnMnglNames = reverse(unmangleArray(@MnglNames));
        foreach my $FuncName (sort keys(%AddedInt))
        {
            if($FuncName =~ /\A_Z/)
            {
                $tr_name{$FuncName} = pop(@UnMnglNames);
                $FuncAttr{2}{$FuncName}{'Signature'} = $tr_name{$FuncName};
            }
        }
    }
}

sub detectWithdrawn()
{
    #Detecting Withdrawn
    foreach my $Int_Name (keys(%{$LibInt{1}}))
    {
        if(not $LibInt{2}{$Int_Name})
        {
            $WithdrawnInt{$Int_Name} = 1;
        }
    }
    #Unmangling Withdrawn
    my @MnglNames = ();
    my @UnMnglNames = ();
    foreach my $FuncName (sort keys(%WithdrawnInt))
    {
        if($FuncName =~ /\A_Z/)
        {
            push(@MnglNames, $FuncName);
        }
    }
    if($#MnglNames > -1)
    {
        @UnMnglNames = reverse(unmangleArray(@MnglNames));
        foreach my $FuncName (sort keys(%WithdrawnInt))
        {
            if($FuncName =~ /\A_Z/)
            {
                $tr_name{$FuncName} = pop(@UnMnglNames);
                $FuncAttr{1}{$FuncName}{'Signature'} = $tr_name{$FuncName};
            }
        }
    }
}

sub get_ShortName($)
{
    my $MnglName = $_[0];
    return $MnglName if($MnglName !~ m/\A(_Z[A-Z]*)([0-9]+)/);
    my $Prefix = $1;
    my $Length = $2;
    return substr($MnglName, length($Prefix)+length($Length), $Length);
}

sub getSymbols_Lib($$)
{
    my $LibVersion = $_[0];
    my $Lib_Path = $_[1];
    my $Lib_SOname = (separatePath($Lib_Path))[1];
    open(SOLIB, "readelf -WhlSsdA $Lib_Path |") || die("Incorrect path to shared object: $Lib_Path\n");
    my $symtab=0; # indicates that we are processing 'symtab' section of 'readelf' output
    while( <SOLIB> )
    {
        if( /'.dynsym'/ ) {
            $symtab=0;
        }
        elsif( /'.symtab'/ ) {
            $symtab=1;
        }
        elsif( /\s*\d+:\s+(\w*)\s+\w+\s+(\w+)\s+(\w+)\s+(\w+)\s+(\w+)\s((\w|@|\.)+)/ ) {
            # (the line of 'readelf' output corresponding to the interface)
    
            # do nothing with symtab (but there are some plans for the future)
            if( $symtab == 1 ) {
                next;
            }
    
            my $fullname=$6; # name, maybe with version
            my $idx=$1;      # offset
            my $type=$2;     # FUNC, OBJECT etc.
            my $bind=$3;     # GLOBAL, WEAK or LOCAL
            my $vis=$4;      # Visibility
            my $Ndx=$5;      # Ndx
    
            # Filter interfaces by their binding, type and visibility
            if( ($bind ne 'WEAK') and ($bind ne 'GLOBAL') ) {
                next;
            }
            if( ($type ne 'FUNC') and ($type ne 'OBJECT') and ($type ne 'COMMON') ) {
                next;
            }
            if( $vis ne 'DEFAULT' ) {
                next;
            }
    
            # Ignore interfaces that are exported form somewhere else
    #       if( $idx !~ /\D|1|2|3|4|5|6|7|8|9/ ) {
            if( $Ndx eq "UND" ) {
                next;
            }
            if( ($Ndx eq "ABS") and ($idx !~ /\D|1|2|3|4|5|6|7|8|9/) ) {
                next;
            }
            
            (my $realname, my $version) = split /\@\@/, $fullname;
            if( not $version ) {
                ($realname, $version) = split /\@/, $fullname;
            }
    
            chomp($realname);
            if($version) {
                chomp($version);
            }
            else {
                $version = '';
            }
            $LibInt{$LibVersion}{$realname} = $Lib_SOname;
            $Library{$LibVersion}{$Lib_SOname} = 1;
            $LibInt_Short{$LibVersion}{get_ShortName($realname)} = $Lib_SOname;
            if(not $Lib_Language{$LibVersion}{$Lib_SOname})
            {
                if($realname =~ m/\A_Z[A-Z]*[0-9]+/)
                {
                    $Lib_Language{$LibVersion}{$Lib_SOname} = "C++";
                }
            }
        }
    }
    close(SOLIB);
}

sub getSoPaths($)
{
    my $LibVersion = $_[0];
    my @SoPaths = ();
    foreach my $Dest (split("\n", $Descriptor{$LibVersion}{'Libs'}))
    {
        $Dest =~ s/\A[ ]*//g;
        $Dest =~ s/[ ]*\Z//g;
        next if(not $Dest);
        if($Descriptor{$LibVersion}{'Dir'})
        {
            $Dest = $Descriptor{$LibVersion}{'Dir'}."/".$Dest if($Dest !~ m{\A/});
        }
        $Dest = $ENV{'PWD'}."/".$Dest if($Dest !~ m{\A/});
        my @SoPaths_Dest = getSOPaths_Dest($Dest);
        foreach (@SoPaths_Dest)
        {
            push(@SoPaths,$_);
        }
    }
    return @SoPaths;
}

sub getSOPaths_Dest($)
{
    my $Dest = $_[0];
    if(`file $Dest` !~ /directory/)
    {
        return $Dest;
    }
    my @AllObjects = split("\n", `find $Dest -name "*\.so*"`);
    my @SOPaths = ();
    foreach my $SharedObject (@AllObjects)
    {
        if(`file $SharedObject` =~ m/shared object/)
        {
            @SOPaths = (@SOPaths, $SharedObject);
        }
    }
    return @SOPaths;
}

sub genDescriptorTemplate()
{
    my $D_Template = "
<version>
    /* Library version */
</version>

<headers>
    /* The list of header paths or directories, one per line */
</headers>

<libs>
    /* The list of shared object paths or directories, one per line */
</libs>

<include_paths>
    /* The list of directories to be searched for header files needed for compiling of library headers, one per line */
    /* This section is not necessary */
</include_paths>

<gcc_options>
    /* Addition gcc options, one per line */
    /* This section is not necessary */
</gcc_options>

<opaque_types>
    /* The list of types that should be skipped while checking, one per line */
    /* This section is not necessary */
</opaque_types>

<internal_functions>
    /* The list of functions that should be skipped while checking, one mangled name per line */
    /* This section is not necessary */
</internal_functions>

<include_preamble>
    /* The list of headers that will be included before each analyzed header */
    /* For example, it is a tree.h for libxml2 and ft2build.h for freetype2 */
    /* This section is not necessary */
    /* This section is useless when -fast option selected */
</include_preamble>\n";

    open(DESCRIPTOR_FORM, ">lib_descriptor.v1");
    print DESCRIPTOR_FORM $D_Template;
    close(DESCRIPTOR_FORM);
    
    open(DESCRIPTOR_FORM, ">lib_descriptor.v2");
    print DESCRIPTOR_FORM $D_Template;
    close(DESCRIPTOR_FORM);
    
    print "You may find generated descriptor templates named lib_descriptor.v1 and lib_descriptor.v2 in the current directory\n";
}

sub getPointerSize()
{
    `mkdir -p temp`;
    open(PROGRAM, ">temp/get_pointer_size.c");
    print PROGRAM "#include <stdio.h>
int main()
{
    printf(\"\%d\", sizeof(int*));
    return 0;
}\n";
    close(PROGRAM);
    system("gcc temp/get_pointer_size.c -o temp/get_pointer_size");
    $PointerSize = `./temp/get_pointer_size`;
    `rm -fr temp`;
}

sub scenario()
{
    HELP_MESSAGE() if (defined $Help);
    if(defined $TestSystem)
    {
        testSystem_cpp();
        testSystem_c();
        exit(0);
    }
    
    if(defined $GenDescriptor)
    {
        genDescriptorTemplate();
        exit(0);
    }
    
    if(not defined $TargetLibraryName)
    {
        print "select library name (option -l <name>)\n";
        exit(1);
    }
    
    if(not $Descriptor{1}{'Path'})
    {
        print "select 1st library descriptor (option -d1 <path>)\n";
        exit(1);
    }
    
    if(not $Descriptor{2}{'Path'})
    {
        print "select 2nd library descriptor (option -d2 <path>)\n";
        exit(1);
    }
    
    readDescriptor(1);
    readDescriptor(2);
    
    $REPORT_PATH = "compat_reports/$TargetLibraryName/".$Descriptor{1}{'Version'}."_to_".$Descriptor{2}{'Version'};
    `mkdir -p $REPORT_PATH`;
    
    if($REPORT_PATH)
    {
        `cd $REPORT_PATH && rm -fr abi_compat_report.html`;
        `mkdir -p $REPORT_PATH/`;
    }
    
    $StartTime = localtime time;
    print "preparation...\n";
    
    getPointerSize();
    
    getSymbols(1);
    getSymbols(2);
    
    headerSearch(1);
    headerSearch(2);
    
    translateSymbols(1);
    translateSymbols(2);
    
    detectAdded();
    detectWithdrawn();
    
    #HEADERS MERGING
    if($AllInOneHeader)
    {
        print "headers checking v.1 ...\n";
        $Version = 1;
        parseHeaders_AllInOne();
        
        print "headers checking v.2 ...\n";
        $Version = 2;
        parseHeaders_AllInOne();
        
        print "headers comparison ...\n";
        mergeHeaders();
    }
    else
    {
        parseHeaders_Separately();
    }
    
    #LIBS MERGING
    mergeLibs();
    
    create_HtmlReport();
    
    if(not $AllInOneHeader)
    {
        if(keys(%HeaderCompileError))
        {
            print "\nWARNING: compilation errors in following headers:\n";
            foreach my $Header (keys(%HeaderCompileError))
            {
                print "$Header ";
            }
            print "\nyou can see compilation errors in the following files:\nheader_compile_errors/$TargetLibraryName/$Descriptor{1}{'Version'}\nheader_compile_errors/$TargetLibraryName/$Descriptor{2}{'Version'}\n";
        }
    }
    
    `rm -fr temp`;
    
    print "\nstarted: $StartTime\n";
    print "finished: ".(localtime time)."\n";
    print "see the results in $REPORT_PATH/abi_compat_report.html\n";
}

#SCENARIO
scenario();
