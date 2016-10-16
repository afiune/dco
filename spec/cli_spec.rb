#
# Copyright 2016, Noah Kantrowitz
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'spec_helper'
require 'git'
require 'shellwords'

describe 'dco' do
  def dco_command *args
    cwd = Dir.pwd
    begin
      Dir.chdir(temp_path)
      capture_output do
        args = Shellwords.split(args.first) if args.length == 1 && args.first.is_a?(String)
        Dco::CLI.start(args)
      end
    ensure
      Dir.chdir(cwd)
    end
  rescue Exception => e
    status  = e.is_a?(SystemExit) ? e.status : 1
    e.output_so_far.define_singleton_method(:exitstatus) { status }
    e.output_so_far
  end
  def self.dco_command *args
    subject { dco_command(*args) }
  end

  def git_init(name: 'Alan Smithee', email: 'asmithee@example.com')
    command "git init && git config user.name '#{name}' && git config user.email '#{email}'"
  end
  def self.git_init(*args)
    before { git_init(*args) }
  end

  let(:repo) { Git.open(temp_path) }

  # Default subject, the most recent commit object.
  subject { repo.log.first }

  describe 'baseline' do
    # Check that the test harness is working.
    git_init
    file 'testing'
    before do
      command 'git add testing'
      command 'git commit -m "harness test"'
    end

    its(:message) { is_expected.to eq 'harness test' }
  end # /describe baseline

  describe 'dco enable' do
    context 'without a git repository' do
      dco_command 'enable -y'

      it do
        expect(subject.exitstatus).to eq 1
        expect(subject.stdout).to eq ''
        expect(subject.stderr).to match /does not appear to be a git repository$/
      end
    end # /context without a git repository

    context 'with an unwritable git repository' do
      git_init
      before { File.chmod(00544, File.join(temp_path, '.git')) }
      dco_command 'enable -y'
      after { File.chmod(00744, File.join(temp_path, '.git')) }

      it do
        expect(subject.exitstatus).to eq 1
        expect(subject.stdout).to eq ''
        expect(subject.stderr).to match /^Git repository at.*? is read-only$/
      end
    end # /context with an unwritable git repository

    context 'with an existing commit-msg script' do
      git_init
      file '.git/hooks/commit-msg', 'SOMETHING ELSE'
      dco_command 'enable -y'

      it do
        expect(subject.exitstatus).to eq 1
        expect(subject.stdout).to eq ''
        expect(subject.stderr).to match /^commit-msg hook already exists, not overwriting$/
      end
    end # /context with an existing commit-msg script

    context 'with a normal commit' do
      git_init
      file 'testing'
      before do
        dco_command 'enable -y'
        command 'git add testing'
        command 'git commit -m "test commit"'
      end

      its(:message) { is_expected.to eq "test commit\n\nSigned-off-by: Alan Smithee <asmithee@example.com>" }
    end # /context with a normal commit

    context 'with a signed-off commit' do
      git_init
      file 'testing'
      before do
        dco_command 'enable -y'
        command 'git add testing'
        command 'git commit -s -m "test commit"'
      end

      its(:message) { is_expected.to eq "test commit\n\nSigned-off-by: Alan Smithee <asmithee@example.com>" }
    end # /context with a signed-off commit

    context 'with enable called twice' do
      git_init
      file 'testing'
      before do
        dco_command 'enable -y'
        dco_command 'enable -y'
        command 'git add testing'
        command 'git commit -m "test commit"'
      end

      its(:message) { is_expected.to eq "test commit\n\nSigned-off-by: Alan Smithee <asmithee@example.com>" }
    end # /context with enable called twice

    context 'without -y' do
      git_init
      dco_command 'enable'

      it do
        expect(subject.exitstatus).to eq 1
        expect(subject.stderr).to eq "Not enabling auto-sign-off without approval\n"
      end
    end # /context without -y
  end # /describe dco enable

  describe 'dco disable' do
    context 'with a normal commit' do
      git_init
      file 'testing'
      before do
        dco_command 'enable -y'
        dco_command 'disable'
        command 'git add testing'
        command 'git commit -m "test commit"'
      end

      its(:message) { is_expected.to eq "test commit" }
    end # /context with a normal commit

    context 'with disable called twice' do
      git_init
      file 'testing'
      before do
        dco_command 'enable -y'
        dco_command 'disable'
        dco_command 'disable'
        command 'git add testing'
        command 'git commit -m "test commit"'
      end

      its(:message) { is_expected.to eq "test commit" }
    end # /context with disable called twice

    context 'with an external commit-msg script' do
      git_init
      file '.git/hooks/commit-msg', 'SOMETHING ELSE'
      dco_command 'disable'

      it do
        expect(subject.exitstatus).to eq 1
        expect(subject.stdout).to eq ''
        expect(subject.stderr).to match /^commit-msg hook is external, not removing$/
      end
    end # /context with an existing commit-msg script
  end # /describe dco disable

  describe 'dco process_commit_message' do
    around do |ex|
      begin
        ENV['GIT_COMMIT'] = 'abcd123'
        ENV['GIT_AUTHOR_NAME'] = 'Alan Smithee'
        ENV['GIT_AUTHOR_EMAIL'] = 'asmithee@example.com'
        ex.run
      ensure
        ENV.delete('GIT_COMMIT')
        ENV.delete('GIT_AUTHOR_NAME')
        ENV.delete('GIT_AUTHOR_EMAIL')
      end
    end

    context 'hook mode' do
      dco_command 'process_commit_message msg'

      RSpec.shared_examples 'process_commit_message hook mode' do |input, output|
        file 'msg', input

        it do
          expect(subject.exitstatus).to eq 0
          expect(subject.stdout).to eq ''
          expect(subject.stderr).to eq ''
          expect(IO.read(File.join(temp_path, 'msg'))).to eq output
        end
      end

      context 'with a normal commit' do
        it_behaves_like 'process_commit_message hook mode', "test commit\n", "test commit\n\nSigned-off-by: Alan Smithee <asmithee@example.com>\n"
      end # /context with a normal commit

      context 'with no trailing newline' do
        it_behaves_like 'process_commit_message hook mode', "test commit", "test commit\n\nSigned-off-by: Alan Smithee <asmithee@example.com>\n"
      end # /context with no trailing newline

      context 'with existing sign-off' do
        it_behaves_like 'process_commit_message hook mode', "test commit\n\nSigned-off-by: Someone Else <other@example.com>\n", "test commit\n\nSigned-off-by: Someone Else <other@example.com>\n"
      end # /context with existing sign-off

      context 'with two existing sign-offs' do
        it_behaves_like 'process_commit_message hook mode', "test commit\n\nSigned-off-by: Alan Smithee <asmithee@example.com>\nSigned-off-by: Someone Else <other@example.com>\n", "test commit\n\nSigned-off-by: Alan Smithee <asmithee@example.com>\nSigned-off-by: Someone Else <other@example.com>\n"
      end # /context with two existing sign-offs
    end # /context hook mode

    context 'filter mode' do
      let(:input) { '' }
      let(:git_ident) { {} }
      let(:stdin) { double('STDIN', read: input) }
      before do
        # Use a let variable instead of calling git_init again in a later before
        # block because we need to all command running before the STDIN stub.
        git_init git_ident
        stub_const('STDIN', stdin)
      end

      context 'with a normal commit' do
        let(:input) { "test commit\n" }
        dco_command 'process_commit_message'

        it do
          expect(subject.exitstatus).to eq 0
          expect(subject.stdout).to eq "test commit\n\nSigned-off-by: Alan Smithee <asmithee@example.com>\n"
          expect(subject.stderr).to eq ''
        end
      end # /context with a normal commit

      context 'with existing sign-off' do
        let(:input) { "test commit\n\nSigned-off-by: Someone Else <other@example.com>\n" }
        dco_command 'process_commit_message'

        it do
          expect(subject.exitstatus).to eq 0
          expect(subject.stdout).to eq "test commit\n\nSigned-off-by: Someone Else <other@example.com>\n"
          expect(subject.stderr).to eq ''
        end
      end # /context with existing sign-off

      context 'with --behalf' do
        let(:input) { "test commit\n" }
        let(:git_ident) { {name: 'Someone Else', email: 'other@example.com'} }
        dco_command 'process_commit_message --behalf http://example.com/'

        it do
          expect(subject.exitstatus).to eq 0
          expect(subject.stdout).to eq "test commit\n\nSigned-off-by: Alan Smithee <asmithee@example.com>\nSign-off-executed-by: Someone Else <other@example.com>\nApproved-at: http://example.com/\n"
          expect(subject.stderr).to eq ''
        end
      end # /context with --behalf

      context 'with someone elses commit' do
        let(:input) { "test commit\n" }
        let(:git_ident) { {name: 'Someone Else', email: 'other@example.com'} }
        dco_command 'process_commit_message'

        it do
          expect(subject.exitstatus).to eq 1
          expect(subject.stdout).to eq "test commit\n"
          expect(subject.stderr).to eq "Author mismatch on commit abcd123: asmithee@example.com vs other@example.com\n"
        end
      end # /context with someone elses commit

      context 'with --repo' do
        let(:input) { "test commit\n" }
        subject { dco_command "process_commit_message --repo '#{temp_path}'" }

        it do
          expect(subject.exitstatus).to eq 0
          expect(subject.stdout).to eq "test commit\n\nSigned-off-by: Alan Smithee <asmithee@example.com>\n"
          expect(subject.stderr).to eq ''
        end
      end # /context with --repo
    end # /context filter mode
  end # /describe dco process_commit_message

  describe 'dco sign' do
    # Create a branch structure for all tests.
    git_init
    file 'testing', 'one'
    before do
      cmds = [
        'git add testing',
        'git commit -m "first commit"',
        'echo two > testing',
        'git commit -a -m "second commit"',
        'git checkout -b mybranch',
      ]
      command cmds.join(' && ')
    end

    context 'with no commits in the branch' do
      dco_command 'sign -y mybranch'

      it do
        expect(subject.exitstatus).to eq 1
        expect(subject.stderr).to eq "Branch mybranch has no commits which require sign-off\n"
      end
    end # /context with no commits in the branch

    context 'with one commit in the branch' do
      before do
        command 'echo three > testing && git commit -a -m "first branch commit"'
      end
      dco_command 'sign -y mybranch'

      it do
        expect(subject.exitstatus).to eq 0
        expect(subject.stdout).to match /^Developer's Certificate of Origin 1\.1$/
        expect(subject.stdout).to match /^Going to sign-off the following commits:\n\* \h{7} Alan Smithee <asmithee@example\.com> first branch commit$/
        expect(repo.log[0].message).to eq "first branch commit\n\nSigned-off-by: Alan Smithee <asmithee@example.com>"
        expect(repo.log[1].message).to eq "second commit"
        expect(repo.log[2].message).to eq "first commit"
      end
    end # /context with one commit in the branch

    context 'with one commit in the branch without -y' do
      before do
        command 'echo three > testing && git commit -a -m "first branch commit"'
      end
      dco_command 'sign mybranch'

      it do
        expect(subject.exitstatus).to eq 1
        expect(subject.stderr).to eq "Not signing off on commits without approval\n"
      end
    end # /context with one commit in the branch without -y

    context 'with two commits in the branch' do
      before do
        command 'echo three > testing && git commit -a -m "first branch commit" && echo four > testing && git commit -a -m "second branch commit"'
      end
      dco_command 'sign -y mybranch'

      it do
        expect(subject.exitstatus).to eq 0
        expect(subject.stdout).to match /^Developer's Certificate of Origin 1\.1$/
        expect(subject.stdout).to match /^Going to sign-off the following commits:\n\* \h{7} Alan Smithee <asmithee@example\.com> second branch commit\n\* \h{7} Alan Smithee <asmithee@example\.com> first branch commit$/
        expect(repo.log[0].message).to eq "second branch commit\n\nSigned-off-by: Alan Smithee <asmithee@example.com>"
        expect(repo.log[1].message).to eq "first branch commit\n\nSigned-off-by: Alan Smithee <asmithee@example.com>"
        expect(repo.log[2].message).to eq "second commit"
        expect(repo.log[3].message).to eq "first commit"
      end
    end # /context with two commits in the branch

    context 'with a branch that has a merge commit' do
      before do
        command('echo three > other && ' \
          'git add other && ' \
          'git commit -a -m "first branch commit" && ' \
          'git checkout master && ' \
          'echo three > testing && ' \
          'git commit -a -m "third commit" && ' \
          'git checkout mybranch && ' \
          'git merge master && ' \
          'echo four > other && ' \
          'git commit -a -m "second branch commit"')
      end
      dco_command 'sign -y mybranch'

      it do
        expect(subject.exitstatus).to eq 0
        expect(subject.stdout).to match /^Developer's Certificate of Origin 1\.1$/
        expect(subject.stdout).to match /^Going to sign-off the following commits:\n\* \h{7} Alan Smithee <asmithee@example\.com> second branch commit\n\* \h{7} Alan Smithee <asmithee@example\.com> Merge branch 'master' into mybranch\n\* \h{7} Alan Smithee <asmithee@example\.com> first branch commit$/
        # Ordering is unstable because of the merge.
        commits = repo.log.map {|c| c.message }
        expect(commits.size).to eq 6
        expect(commits).to include "second branch commit\n\nSigned-off-by: Alan Smithee <asmithee@example.com>"
        expect(commits).to include "Merge branch 'master' into mybranch\n\nSigned-off-by: Alan Smithee <asmithee@example.com>"
        expect(commits).to include "first branch commit\n\nSigned-off-by: Alan Smithee <asmithee@example.com>"
        expect(commits).to include "third commit"
        expect(commits).to include "second commit"
        expect(commits).to include "first commit"
      end
    end # /context with a branch that has a merge commit

    context 'with behalf mode enabled' do
      before do
        command 'echo three > testing && git commit -a -m "first branch commit" && echo four > testing && git commit -a -m "second branch commit"'
        git_init(name: 'Commiter McCommiterface', email: 'other@example.com')
      end
      dco_command 'sign -y mybranch -b https://github.com/chef/chef/pulls/1234'

      it do
        expect(subject.exitstatus).to eq 0
        expect(subject.stdout).to_not match /^Developer's Certificate of Origin 1\.1$/
        expect(subject.stdout).to match /^Going to sign-off the following commits:\n\* \h{7} Alan Smithee <asmithee@example\.com> second branch commit\n\* \h{7} Alan Smithee <asmithee@example\.com> first branch commit$/
        expect(repo.log[0].message).to eq "second branch commit\n\nSigned-off-by: Alan Smithee <asmithee@example.com>\nSign-off-executed-by: Commiter McCommiterface <other@example.com>\nApproved-at: https://github.com/chef/chef/pulls/1234"
        expect(repo.log[1].message).to eq "first branch commit\n\nSigned-off-by: Alan Smithee <asmithee@example.com>\nSign-off-executed-by: Commiter McCommiterface <other@example.com>\nApproved-at: https://github.com/chef/chef/pulls/1234"
        expect(repo.log[2].message).to eq "second commit"
        expect(repo.log[3].message).to eq "first commit"
      end
    end # /context with behalf mode enabled

    context 'with someone elses commits' do
      before do
        command 'echo three > testing && git commit -a -m "first branch commit" && echo four > testing && git commit -a -m "second branch commit"'
        git_init(name: 'Commiter McCommiterface', email: 'other@example.com')
      end
      dco_command 'sign -y mybranch'

      it do
        expect(subject.exitstatus).to eq 1
        expect(subject.stderr).to eq "Branch mybranch contains commits not authored by you. Please use the --behalf flag when signing off for another contributor\n"
      end
    end # /context with someone elses commits

    context 'with an invalid branch' do
      dco_command 'sign -y master'

      it do
        expect(subject.exitstatus).to eq 1
        expect(subject.stderr).to eq "Cannot use master for both the base and target branch\n"
      end
    end # /context with an invalid branch

    context 'with an implicit branch' do
      before do
        command 'echo three > testing && git commit -a -m "first branch commit"'
      end
      dco_command 'sign -y'

      it do
        expect(subject.exitstatus).to eq 0
        expect(subject.stdout).to match /^Developer's Certificate of Origin 1\.1$/
        expect(subject.stdout).to match /^Going to sign-off the following commits:\n\* \h{7} Alan Smithee <asmithee@example\.com> first branch commit$/
        expect(repo.log[0].message).to eq "first branch commit\n\nSigned-off-by: Alan Smithee <asmithee@example.com>"
        expect(repo.log[1].message).to eq "second commit"
        expect(repo.log[2].message).to eq "first commit"
      end
    end # /context with an implicit branch

    context 'with an implicit invalid branch' do
      before { command 'git checkout master' }
      dco_command 'sign -y'

      it do
        expect(subject.exitstatus).to eq 1
        expect(subject.stderr).to eq "Cannot use master for both the base and target branch\n"
      end
    end # /context with an implicit invalid branch

    context 'with an existing backup pointer' do
      before do
        command 'echo three > testing && git commit -a -m "first branch commit"'
        dco_command 'sign -y mybranch'
        command 'echo four > testing && git commit -a -m "second branch commit"'
      end
      dco_command 'sign -y mybranch'

      it do
        expect(subject.exitstatus).to eq 0
        expect(subject.stdout).to match /^Developer's Certificate of Origin 1\.1$/
        expect(subject.stdout).to match /^Going to sign-off the following commits:\n\* \h{7} Alan Smithee <asmithee@example\.com> second branch commit$/
        expect(repo.log[0].message).to eq "second branch commit\n\nSigned-off-by: Alan Smithee <asmithee@example.com>"
        expect(repo.log[1].message).to eq "first branch commit\n\nSigned-off-by: Alan Smithee <asmithee@example.com>"
        expect(repo.log[2].message).to eq "second commit"
        expect(repo.log[3].message).to eq "first commit"
      end
    end # /context with an existing backup pointer

    context 'with an existing backup pointer without -y' do
      before do
        command 'echo three > testing && git commit -a -m "first branch commit"'
        dco_command 'sign -y mybranch'
        command 'echo four > testing && git commit -a -m "second branch commit"'
      end
      dco_command 'sign mybranch'

      it do
        expect(subject.exitstatus).to eq 1
        expect(subject.stderr).to eq "Backup ref present, not continuing\n"
      end
    end # /context with an existing backup pointer without -y
  end # /describe dco sign
end
