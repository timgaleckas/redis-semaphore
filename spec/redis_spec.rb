require File.dirname(__FILE__) + '/spec_helper'

describe "redis" do
  before(:all) do
    # use database 15 for testing so we dont accidentally step on you real data
    @redis = Redis.new :db => 15
    @semaphore = Redis::Semaphore.new(:my_semaphore, @redis)
  end

  before(:each) do
    @redis.flushdb
  end

  after(:each) do
    @redis.flushdb
  end

  after(:all) do
    @redis.quit
  end

  it "should be unlocked from the start" do
    @semaphore.locked?.should == false
  end

  it "should lock and unlock" do
    @semaphore.lock
    @semaphore.locked?.should == true
    @semaphore.unlock
    @semaphore.locked?.should == false
  end

  it "should not lock twice as a mutex" do
    @semaphore.lock
    @semaphore.lock(1).should == false
  end

  it "should not lock three times when only two available" do
    multisem = Redis::Semaphore.new(:my_semaphore2, 2, @redis)
    multisem.lock.should == true
    multisem.lock(1).should == true
    multisem.lock(1).should == false
  end

  it "should reuse the same index for 5 calls in serial" do
    multisem = Redis::Semaphore.new(:my_semaphore5_serial, 5, @redis)
    ids = []
    5.times do
      multisem.lock(1) do |i|
        ids << i
      end
    end
    ids.size.should == 5
    ids.uniq.size.should == 1
  end

  it "should have 5 different indexes for 5 parallel calls" do
    multisem = Redis::Semaphore.new(:my_semaphore5_parallel, 5, @redis)
    ids = []
    multisem.lock(1) do |i|
      ids << i
      multisem.lock(1) do |i|
        ids << i
        multisem.lock(1) do |i|
          ids << i
          multisem.lock(1) do |i|
            ids << i
            multisem.lock(1) do |i|
              ids << i
              multisem.lock(1) do |i|
                ids << i
              end.should == false
            end
          end
        end
      end
    end
    (0..4).to_a.should == ids
  end

  it "should execute the given code block" do
    code_executed = false
    @semaphore.lock do
      code_executed = true
    end
    code_executed.should == true
  end

  it "should pass an exception right through" do
    lambda do
      @semaphore.lock do
        raise Exception, "redis semaphore exception"
      end
    end.should raise_error(Exception, "redis semaphore exception")
  end

  it "should not leave the semaphore locked after raising an exception" do
    lambda do
      @semaphore.lock do
        raise Exception
      end
    end.should raise_error

    @semaphore.locked?.should == false
  end

  it "should restore resources of stale clients" do
    hyper_aggressive_sem = Redis::Semaphore.new(:hyper_aggressive_sem, 1, @redis)
    hyper_aggressive_sem.stale_client_timeout = 1
    hyper_aggressive_sem.lock(1).should == true
    hyper_aggressive_sem.lock(1).should == false #because it is locked as expected
    hyper_aggressive_sem.lock(1).should == true  #becuase it is assumed that the first
                                                 #lock is no longer valid since the
                                                 #client could've been killed
  end

  it "should be backward compatible with previous exist values" do
    @redis.set("SEMAPHORE::my_semaphore::EXISTS",1)
    @semaphore.lock
  end
end
