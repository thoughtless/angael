# Angael

Angael is a lightweight library for running repetitive background processes.

## Documentation

Angael's model of running background processes involves two classes: a worker and a manager.

Theoretically you do not need to modify Angael's built in manager (Angael::Manager).
It already has the basic logic for starting and stopping the workers.

Since workers are very different depending on the task at hand, Angael doesn't
include a Worker class. Instead there is just a module (Angael::Worker) which 
you can include into your own class.
When you include Angael::Worker your class is expected to define a method called
`work`. This method will be called repeatedly until the the worker is stopped.
Also note, Angael::Worker defines an initialize method. If you require your own
initializer, take care that you either call super or you set the appropriate
instance variables.

## Example


```
class MailMan
  include Angael::Worker
  def work
    deliver_letters
  end

  def deliver_letters
    # Your cool code
  end
end

mail_man_manager = Angael::Manager.new(MailMan)

# This will loop forever until it receives a SIGINT or SIGTERM.
mail_man_manager.start!

```

## Setup

Gemfile

    gem 'angael', :git => 'git://github.com/thoughtless/angael.git'

`bundle install`


## Contribute

See [http://github.com/thoughtless/angael](http://github.com/thoughtless/angael)
