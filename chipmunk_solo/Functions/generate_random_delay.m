function random_delay = generate_random_delay (lambda, minimum, maximum)
if maximum == minimum
    random_delay = minimum;
    return
end
x = -log(rand)/lambda;
random_delay = mod(x, maximum - minimum) + minimum;
end
