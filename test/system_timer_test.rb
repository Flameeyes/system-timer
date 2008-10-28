 $: << File.dirname(__FILE__) + '/../lib'
 $: << File.dirname(__FILE__) + '/../ext/system_timer'
 $: << File.dirname(__FILE__) + "/../vendor/gems/dust-0.1.6/lib"
 $: << File.dirname(__FILE__) + "/../vendor/gems/mocha-0.9.1/lib"
require 'test/unit'
require 'system_timer'
require 'dust'
require 'mocha'
require 'stringio'
require "open-uri"

functional_tests do
  
  ERROR_MARGIN = 2

  # SystemTimer.enable_debug
        
  test "original_ruby_sigalrm_handler is nil after reset" do
    SystemTimer.send(:install_ruby_sigalrm_handler)
    SystemTimer.send(:reset_original_ruby_sigalrm_handler)
    assert_nil SystemTimer.send(:original_ruby_sigalrm_handler)
  end  
  
  test "original_ruby_sigalrm_handler is set to existing handler after install_ruby_sigalrm_handler" do
    SystemTimer.expects(:trap).with('SIGALRM').returns(:an_existing_handler)
    SystemTimer.send(:install_ruby_sigalrm_handler)
    assert_equal :an_existing_handler, SystemTimer.send(:original_ruby_sigalrm_handler)
  end
  
  test "restore_original_ruby_sigalrm_handler traps sigalrm using original_ruby_sigalrm_handler" do
    SystemTimer.stubs(:original_ruby_sigalrm_handler).returns(:the_original_handler)
    SystemTimer.expects(:trap).with('SIGALRM', :the_original_handler)
    SystemTimer.send :restore_original_ruby_sigalrm_handler
  end  
  
  test "restore_original_ruby_sigalrm_handler resets original_ruby_sigalrm_handler" do
    SystemTimer.stubs(:trap)
    SystemTimer.expects(:reset_original_ruby_sigalrm_handler)
    SystemTimer.send :restore_original_ruby_sigalrm_handler
  end  
  
  test "restore_original_ruby_sigalrm_handler reset SIGALRM handler to default when original_ruby_sigalrm_handler is nil" do
    SystemTimer.stubs(:original_ruby_sigalrm_handler)
    SystemTimer.expects(:trap).with('SIGALRM', 'DEFAULT')
    SystemTimer.stubs(:reset_original_ruby_sigalrm_handler)
    SystemTimer.send :restore_original_ruby_sigalrm_handler
  end  
  
  test "restore_original_ruby_sigalrm_handler resets original_ruby_sigalrm_handler when trap raises" do
    SystemTimer.stubs(:trap).returns(:the_original_handler)
    SystemTimer.send(:install_ruby_sigalrm_handler)
    SystemTimer.expects(:trap).raises("next time maybe...")
    SystemTimer.expects(:reset_original_ruby_sigalrm_handler)
  
    SystemTimer.send(:restore_original_ruby_sigalrm_handler) rescue nil
  end  
  
  test "timeout_after raises TimeoutError if block takes too long" do
    assert_raises(Timeout::Error) do
      SystemTimer.timeout_after(1) {sleep 5}
    end
  end
  
  test "timeout_after does not raises Timeout Error if block completes in time" do
    SystemTimer.timeout_after(5) {sleep 1}
  end
  
  test "timeout_after returns the value returned by the black" do
    assert_equal :block_value, SystemTimer.timeout_after(1) {:block_value}
  end
  
  test "timeout_after raises TimeoutError in thread that called timeout_after" do
    raised_thread = nil
    other_thread = Thread.new do 
      begin
        SystemTimer.timeout_after(1) {sleep 5}
        flunk "Should have timed out"
      rescue Timeout::Error
        raised_thread = Thread.current
      end
    end
    
    other_thread.join 
    assert_equal other_thread, raised_thread
  end
  
  test "cancelling a timer that was installed restores previous ruby handler for SIG_ALRM" do    
    begin
      fake_original_ruby_handler = proc {}
      initial_ruby_handler = trap "SIGALRM", fake_original_ruby_handler
      SystemTimer.install_timer(3)
      SystemTimer.cleanup_timer
      assert_equal fake_original_ruby_handler, trap("SIGALRM", "IGNORE")    
    ensure  # avoid interfering with test infrastructure
      trap("SIGALRM", initial_ruby_handler) if initial_ruby_handler  
    end
  end
   
  test "debug_enabled returns true after enabling debug" do
    begin
      SystemTimer.disable_debug
      SystemTimer.enable_debug
      assert_equal true, SystemTimer.debug_enabled?
    ensure
      SystemTimer.disable_debug
    end
  end 
  
  test "debug_enabled returns false after disable debug" do
    begin
      SystemTimer.enable_debug
      SystemTimer.disable_debug
      assert_equal false, SystemTimer.debug_enabled?
    ensure
      SystemTimer.disable_debug
    end 
  end
  
  test "timeout offers an API fully compatible with timeout.rb" do
    assert_raises(Timeout::Error) do
      SystemTimer.timeout(1) {sleep 5}
    end
  end
  
  test "while exact timeouts cannot be guaranted the timeout should not exceed twiced the provided timeout" do
    start = Time.now
    begin
      SystemTimer.timeout_after(1) do 
        open "http://www.invalid.domain.comz"
      end
      raise "should never get there"
    rescue SocketError => e
    rescue Timeout::Error => e
    end
    elapsed = Time.now - start
    assert elapsed < 2
  end
  
  test "timeout are enforced on system calls" do
    assert_timeout_within(3) do
      SystemTimer.timeout(3) do
         sleep 60
      end
    end
  end

  test "timeout work when spawning a different thread" do
    assert_timeout_within(3) do
      thread = Thread.new do
        SystemTimer.timeout(3) do
           sleep 60
        end
      end
      thread.join
    end
  end
  
  def assert_timeout_within(expected_timeout_in_seconds, &block)
    start = Time.now
    yield
    flunk "Did not timeout as expected!"
  rescue Timeout::Error    
    elapsed = Time.now - start
    assert elapsed < ERROR_MARGIN * expected_timeout_in_seconds, 
           "Timed out after #{elapsed} seconds, expected #{expected_timeout_in_seconds}"
  end
  
end