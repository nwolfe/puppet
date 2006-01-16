# Manage Unix groups.  This class is annoyingly complicated; There
# is some variety in whether systems use 'groupadd' or 'addgroup', but OS X
# significantly complicates the picture by using NetInfo.  Eventually we
# will also need to deal with systems that have their groups hosted elsewhere
# (e.g., in LDAP).  That will likely only be a problem for OS X, since it
# currently does not use the POSIX interfaces, since lookupd's cache screws
# things up.

require 'etc'
require 'facter'
require 'puppet/type/state'
require 'puppet/type/nameservice'

module Puppet
    newtype(:group, Puppet::Type::NSSType) do
        @doc = "Manage groups.  This type can only create groups.  Group
            membership must be managed on individual users."

        case Facter["operatingsystem"].value
        when "Darwin":
            @parentstate = Puppet::NameService::NetInfo::NetInfoState
            @parentmodule = Puppet::NameService::NetInfo
        else
            @parentstate = Puppet::NameService::ObjectAdd::ObjectAddGroup
            @parentmodule = Puppet::NameService::ObjectAdd
        end

        newstate(:gid, @parentstate) do
            desc "The group ID.  Must be specified numerically.  If not
                specified, a number will be picked, which can result in ID
                differences across systems and thus is not recommended.  The
                GID is picked according to local system standards."

            def autogen
                highest = 0
                Etc.group { |group|
                    if group.gid > highest
                        unless group.gid > 65000
                            highest = group.gid
                        end
                    end
                }

                return highest + 1
            end

            munge do |gid|
                case gid
                when String
                    if gid =~ /^[-0-9]+$/
                        gid = Integer(gid)
                    else
                        raise Puppet::Error, "Invalid GID %s" % gid
                    end
                when Symbol
                    unless gid == :auto or gid == :absent
                        raise Puppet::DevError, "Invalid GID %s" % gid
                    end
                    if gid == :auto
                        unless self.class.autogen?
                            gid = autogen()
                            @parent.log "autogenerated value as %s" % gid
                        end
                    end
                end

                self.info "Setting gid to %s" % gid

                return gid
            end
        end

        class << self
            attr_accessor :netinfodir
        end

        @netinfodir = "groups"

        newparam(:name) do
            desc "The group name.  While naming limitations vary by
                system, it is advisable to keep the name to the degenerate
                limitations, which is a maximum of 8 characters beginning with
                a letter."

            isnamevar
        end

        def exists?
            self.class.parentmodule.exists?(self)
        end

        def getinfo(refresh = false)
            if @groupinfo.nil? or refresh == true
                begin
                    @groupinfo = Etc.getgrnam(self.name)
                rescue ArgumentError => detail
                    @groupinfo = nil
                end
            end

            @groupinfo
        end

        def initialize(hash)
            @groupinfo = nil
            super
        end

        def retrieve
            if self.exists?
                super
            else
                # the group does not exist
                unless @states.include?(:gid)
                    self[:gid] = :auto
                end

                @states.each { |name, state|
                    state.is = :absent
                }

                return
            end
        end
    end
end

# $Id$
