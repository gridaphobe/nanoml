import csv
import matplotlib
import matplotlib.pyplot as plt
import numpy as np

BUCKETS = range(500, 3001, 500)
COLORS=['#348ABD', '#7A68A6', '#A60628', '#467821', '#CF4457', '#188487', '#E24A33']

SAFE = ['S', 'T']
SAFE_L = ['Safe', 'Timeout']
UNSAFE = ['U', 'B', 'D'] #, 'O']
UNSAFE_L = ['Unsafe', 'Unbound', 'Diverge'] #, 'Output']
ALL = UNSAFE + SAFE
ALL_L = UNSAFE_L + SAFE_L

def read_csv(f):
    with open(f) as f:
        return list(csv.reader(f))

def cumulative_coverage(data):
    headers = data[0]
    data = data[1:]
    return [(l, len([r for r in data
                     if int(r[1]) <= l
                     and r[4] in UNSAFE])
             / float(len(data)))
            for l in BUCKETS]

def plot_coverage(data):
    xy = cumulative_coverage(data)

    N = len(xy)
    ind = np.arange(N)    # the x locations for the groups
    width = 0.5       # the width of the bars: can also be len(x) sequence

    p1 = plt.bar(ind, [r[1] for r in xy], width,
                 color=COLORS[0])

    plt.xlabel('Timeout (steps)')
    plt.ylabel('% witnesses found')
    plt.title('Cumulative Coverage')
    plt.xticks(ind + width/2.0, [r[0] for r in xy])
    plt.yticks(np.arange(0.0, 1.1, 0.1))
    plt.legend((p1[0],), ('Seminal',))
    # plt.legend((p1[0], p2[0]), ('Men', 'Women'))

    plt.show()

def plot_distrib(data, label):
    data = data[1:]
    rs = [len([r for r in data if r[4] == o])
          for o in ALL]

    # N = len(xy)
    # ind = np.arange(N)    # the x locations for the groups
    # width = 0.5       # the width of the bars: can also be len(x) sequence

    plt.axes(aspect=1)
    p1 = plt.pie(rs, labels=ALL_L,
                 autopct='%.1f%%',
                 colors=COLORS,
                 shadow=True)

    # p2 = plt.pie(rs, labels=ALL_L,
    #              autopct='%.1f%%',
    #              shadow=True)

    plt.title('Distribution of Results (%s)' % label)
    plt.legend()
    # plt.xticks(ind + width/2.0, [r[0] for r in xy])
    # plt.yticks(np.arange(0.0, 1.1, 0.1))
    # plt.legend((p1[0],), ('Seminal',))
    # plt.legend((p1[0], p2[0]), ('Men', 'Women'))

    plt.show()
