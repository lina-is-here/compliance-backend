# frozen_string_literal: true

require 'test_helper'

# A class to test importing from a Datastream file
class DatastreamDownloaderTest < ActiveSupport::TestCase
  setup do
    @ssgs = [
      SupportedSsg.new(
        id: 'rhel-7.9-scap-security-guide-0.1.49-13.el7',
        package: 'scap-security-guide-0.1.49-13.el7',
        version: '0.1.49',
        os_major_version: '7',
        os_minor_version: '9'
      )
    ]
  end

  test 'dowlnoads ssg datastream files' do
    @ds_file = file_fixture('ssg-rhel7-ds.xml')
    downloaded = mock
    downloaded.expects(:path).returns(@ds_file.to_s)
    downloaded.expects(:close)

    SafeDownloader.expects(:download).returns(downloaded).with do |url|
      url.include?('/rhel7') && url =~ %r{/ssg-rhel7-ds.xml$}
    end

    downloader = DatastreamDownloader.new(@ssgs)
    yielded = 0
    downloader.download_datastreams do |file|
      assert @ds_file.size, File.size(file)
      yielded += 1
    end

    assert_equal 1, yielded
    assert_audited 'Dowloaded datastream file'
  end

  test 'audits download failure' do
    SafeDownloader.expects(:download).raises(StandardError)

    downloader = DatastreamDownloader.new(@ssgs)
    yielded = 0
    assert_raises StandardError do
      downloader.download_datastreams { yielded += 1 }
    end

    assert_audited 'Failed to dowload datastream file'
    assert_equal 0, yielded
  end

  test 'uses default supported ssgs' do
    assert DatastreamDownloader.new.instance_variable_get('@ssgs')
  end

  test 'deduplicates revisions per OS major' do
    ssgs = [
      SupportedSsg.new(
        id: 'rhel-7.9-scap-security-guide-0.1.49-13.el7',
        package: 'scap-security-guide-0.1.49-13.el7',
        version: '0.1.49',
        os_major_version: '7',
        os_minor_version: '9'
      ),
      SupportedSsg.new(
        id: 'rhel-7.8-scap-security-guide-0.1.49-12.el7',
        package: 'scap-security-guide-0.1.49-12.el7',
        version: '0.1.49',
        os_major_version: '7',
        os_minor_version: '8'
      ),
      SupportedSsg.new(
        id: 'rhel-8.4-scap-security-guide-0.1.57-3.el8_4',
        package: 'scap-security-guide-0.1.57-3.el8_4',
        version: '0.1.57',
        os_major_version: '8',
        os_minor_version: '4'
      ),
      SupportedSsg.new(
        id: 'rhel-8.5-scap-security-guide-0.1.57-5.el8',
        package: 'scap-security-guide-0.1.57-5.el8',
        version: '0.1.57',
        os_major_version: '8',
        os_minor_version: '5'
      )
    ]

    SupportedSsg.stubs(:all).returns(ssgs)
    result = DatastreamDownloader.new.default_supported_ssgs.map(&:package)

    assert_includes(result, 'scap-security-guide-0.1.57-5.el8')
    assert_includes(result, 'scap-security-guide-0.1.49-13.el7')

    assert_not_includes(result, 'scap-security-guide-0.1.57-3.el8_4')
    assert_not_includes(result, 'scap-security-guide-0.1.49-12.el7')
  end
end
